#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#define REG_ID          0x000
#define REG_CONTROL     0x008
#define REG_STATUS      0x00c
#define REG_BYTES       0x010
#define REG_BASE        0x014
#define REG_MODE        0x018
#define REG_SEED        0x01c
#define REG_DDS_FTW     0x02c
#define REG_DDS_CONTROL 0x030
#define EXPECTED_ID     0x41443932u
#define ST_LINK         (1u<<0)
#define ST_CALIB        (1u<<1)
#define ST_OVERFLOW     (1u<<5)
#define ST_AXI_ERROR    (1u<<6)
#define ST_BUFFER_READY (1u<<7)

static double seconds(const struct timespec *a,const struct timespec *b){
    return (b->tv_sec-a->tv_sec)+(b->tv_nsec-a->tv_nsec)/1e9;
}

static void usage(const char *name){
    fprintf(stderr,
        "Usage: %s [--mode adc|ramp] [--bytes N] [--base N] [--seed N] "
        "[--freq HZ] [--mclk HZ] [--triangle] [--out FILE]\n",name);
}

int main(int argc,char **argv){
    const char *user_dev="/dev/xdma0_user";
    const char *c2h_dev="/dev/xdma0_c2h_0";
    const char *out_name="capture.bin";
    const char *mode_name="adc";
    size_t bytes=1024*1024;
    uint32_t base=0,seed=0,mode=0;
    double dds_freq=0.0,dds_mclk=25000000.0;
    int dds_triangle=0;

    for(int i=1;i<argc;i++){
        if(!strcmp(argv[i],"--mode")&&i+1<argc)mode_name=argv[++i];
        else if(!strcmp(argv[i],"--bytes")&&i+1<argc)bytes=strtoull(argv[++i],0,0);
        else if(!strcmp(argv[i],"--base")&&i+1<argc)base=strtoul(argv[++i],0,0);
        else if(!strcmp(argv[i],"--seed")&&i+1<argc)seed=strtoul(argv[++i],0,0);
        else if(!strcmp(argv[i],"--freq")&&i+1<argc)dds_freq=strtod(argv[++i],0);
        else if(!strcmp(argv[i],"--mclk")&&i+1<argc)dds_mclk=strtod(argv[++i],0);
        else if(!strcmp(argv[i],"--triangle"))dds_triangle=1;
        else if(!strcmp(argv[i],"--out")&&i+1<argc)out_name=argv[++i];
        else{usage(argv[0]);return 2;}
    }

    if(!strcmp(mode_name,"adc"))mode=0;
    else if(!strcmp(mode_name,"ramp"))mode=1;
    else{usage(argv[0]);return 2;}
    if(!bytes||bytes>UINT32_MAX||(bytes&15)||(base&15)){
        fprintf(stderr,"bytes and base must be nonzero/valid and 16-byte aligned\n");
        return 2;
    }
    if(dds_freq<0.0||dds_mclk<=0.0||dds_freq>=dds_mclk/2.0){
        fprintf(stderr,"DDS frequency must be nonnegative and below half of MCLK\n");
        return 2;
    }

    int ufd=open(user_dev,O_RDWR|O_SYNC);
    if(ufd<0){perror(user_dev);return 1;}
    volatile uint32_t *r=mmap(NULL,4096,PROT_READ|PROT_WRITE,MAP_SHARED,ufd,0);
    if(r==MAP_FAILED){perror("mmap user BAR");close(ufd);return 1;}
    if(r[REG_ID/4]!=EXPECTED_ID){
        fprintf(stderr,"unexpected ID 0x%08x\n",r[REG_ID/4]);return 1;
    }
    if((r[REG_STATUS/4]&(ST_LINK|ST_CALIB))!=(ST_LINK|ST_CALIB)){
        fprintf(stderr,"PCIe link or memory calibration not ready: 0x%08x\n",r[REG_STATUS/4]);
        return 1;
    }

    if(dds_freq>0.0){
        uint32_t ftw=(uint32_t)(dds_freq*268435456.0/dds_mclk+0.5);
        r[REG_DDS_FTW/4]=ftw&0x0fffffffu;
        r[REG_DDS_CONTROL/4]=(dds_triangle?1u:0u)|2u;
        struct timespec dds_delay={0,10000000};
        nanosleep(&dds_delay,NULL);
        printf("AD9833 configured: %.3f Hz, FTW=0x%07x, waveform=%s\n",
            dds_freq,ftw&0x0fffffffu,dds_triangle?"triangle":"sine");
    }

    r[REG_CONTROL/4]=2;
    r[REG_BYTES/4]=(uint32_t)bytes;
    r[REG_BASE/4]=base;
    r[REG_MODE/4]=mode;
    r[REG_SEED/4]=seed;
    struct timespec t0,t1,deadline;
    clock_gettime(CLOCK_MONOTONIC,&t0);
    deadline=t0;deadline.tv_sec+=10;
    r[REG_CONTROL/4]=1;
    for(;;){
        uint32_t status=r[REG_STATUS/4];
        if(status&ST_BUFFER_READY)break;
        if(status&(ST_OVERFLOW|ST_AXI_ERROR)){
            fprintf(stderr,"capture failed, status=0x%08x\n",status);return 1;
        }
        clock_gettime(CLOCK_MONOTONIC,&t1);
        if(t1.tv_sec>deadline.tv_sec||(t1.tv_sec==deadline.tv_sec&&t1.tv_nsec>deadline.tv_nsec)){
            fprintf(stderr,"capture timeout, status=0x%08x\n",status);return 1;
        }
        struct timespec delay={0,1000000};
        nanosleep(&delay,NULL);
    }
    clock_gettime(CLOCK_MONOTONIC,&t1);
    double capture_s=seconds(&t0,&t1);

    int cfd=open(c2h_dev,O_RDONLY);
    if(cfd<0){perror(c2h_dev);return 1;}
    void *buffer=NULL;
    if(posix_memalign(&buffer,4096,bytes)){fprintf(stderr,"allocation failed\n");return 1;}
    size_t total=0;
    clock_gettime(CLOCK_MONOTONIC,&t0);
    while(total<bytes){
        ssize_t count=pread(cfd,(uint8_t*)buffer+total,bytes-total,(off_t)base+total);
        if(count<0&&errno==EINTR)continue;
        if(count<=0){perror("C2H pread");return 1;}
        total+=(size_t)count;
    }
    clock_gettime(CLOCK_MONOTONIC,&t1);
    double dma_s=seconds(&t0,&t1);

    size_t errors=0;
    const uint32_t *words=buffer;
    for(size_t j=0;j<bytes/4;j++){
        uint32_t expected=seed+(uint32_t)j;
        int mismatch=mode?(words[j]!=expected):((words[j]&0xf000f000u)!=0);
        if(mismatch){
            if(errors<8)fprintf(stderr,"mismatch[%zu] got=%08x expected=%08x\n",j,words[j],expected);
            errors++;
        }
    }

    FILE *out=fopen(out_name,"wb");
    if(!out||fwrite(buffer,1,bytes,out)!=bytes){perror(out_name);return 1;}
    fclose(out);
    printf("mode=%s bytes=%zu capture=%.3f MB/s C2H=%.3f MB/s errors=%zu status=0x%08x\n",
        mode_name,bytes,bytes/capture_s/1e6,bytes/dma_s/1e6,errors,r[REG_STATUS/4]);

    free(buffer);close(cfd);munmap((void*)r,4096);close(ufd);
    return errors?1:0;
}
