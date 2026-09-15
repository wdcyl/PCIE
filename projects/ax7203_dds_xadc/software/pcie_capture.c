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

#define REG_ID 0x000
#define REG_CONTROL 0x008
#define REG_STATUS 0x00c
#define REG_BYTES 0x010
#define REG_MODE 0x014
#define REG_SEED 0x018
#define REG_DDS_FTW 0x01c
#define REG_DDS_CTRL 0x020
#define EXPECTED_ID 0x58414430u

static uint32_t prbs_next(uint32_t v) {
    return (v << 1) | (((v >> 31) ^ (v >> 21) ^ (v >> 1) ^ v) & 1u);
}

static double elapsed(const struct timespec *a, const struct timespec *b) {
    return (b->tv_sec-a->tv_sec)+(b->tv_nsec-a->tv_nsec)/1e9;
}

static void usage(const char *name) {
    fprintf(stderr,
        "Usage: %s [--mode xadc|ramp|prbs] [--bytes N] [--out FILE]\n"
        "          [--freq HZ --mclk HZ] [--triangle] [--seed N]\n",name);
}

int main(int argc,char **argv) {
    const char *user_dev="/dev/xdma0_user", *c2h_dev="/dev/xdma0_c2h_0";
    const char *out_name="capture.bin", *mode_name="xadc";
    size_t bytes=1024*1024; uint32_t mode=0,seed=0; double freq=0,mclk=25000000.0;
    int triangle=0,i; size_t j;
    for(i=1;i<argc;i++) {
        if(!strcmp(argv[i],"--mode")&&i+1<argc) mode_name=argv[++i];
        else if(!strcmp(argv[i],"--bytes")&&i+1<argc) bytes=strtoull(argv[++i],0,0);
        else if(!strcmp(argv[i],"--out")&&i+1<argc) out_name=argv[++i];
        else if(!strcmp(argv[i],"--freq")&&i+1<argc) freq=strtod(argv[++i],0);
        else if(!strcmp(argv[i],"--mclk")&&i+1<argc) mclk=strtod(argv[++i],0);
        else if(!strcmp(argv[i],"--seed")&&i+1<argc) seed=strtoul(argv[++i],0,0);
        else if(!strcmp(argv[i],"--triangle")) triangle=1;
        else { usage(argv[0]); return 2; }
    }
    if(!strcmp(mode_name,"xadc")) mode=0;
    else if(!strcmp(mode_name,"ramp")) mode=1;
    else if(!strcmp(mode_name,"prbs")) mode=3;
    else { usage(argv[0]); return 2; }
    if(!bytes || bytes>UINT32_MAX || (mode==0 && (bytes&1)) || (mode!=0 && (bytes&3))) {
        fprintf(stderr,"bytes must be nonzero, <= UINT32_MAX, and aligned to sample/word size\n");
        return 2;
    }

    int ufd=open(user_dev,O_RDWR|O_SYNC);
    if(ufd<0) { perror(user_dev); return 1; }
    volatile uint32_t *regs=mmap(NULL,4096,PROT_READ|PROT_WRITE,MAP_SHARED,ufd,0);
    if(regs==MAP_FAILED) { perror("mmap user BAR"); close(ufd); return 1; }
    if(regs[REG_ID/4]!=EXPECTED_ID) {
        fprintf(stderr,"unexpected device ID: 0x%08x\n",regs[REG_ID/4]); return 1;
    }
    if(freq>0) {
        uint64_t ftw=(uint64_t)(freq*268435456.0/mclk+0.5);
        if(ftw>0x0fffffffu) { fprintf(stderr,"DDS frequency is out of range\n"); return 2; }
        regs[REG_DDS_FTW/4]=(uint32_t)ftw;
        regs[REG_DDS_CTRL/4]=(triangle?1u:0u)|2u;
    }
    regs[REG_CONTROL/4]=2u;
    regs[REG_BYTES/4]=(uint32_t)bytes;
    regs[REG_MODE/4]=mode;
    regs[REG_SEED/4]=seed;

    int cfd=open(c2h_dev,O_RDONLY);
    if(cfd<0) { perror(c2h_dev); return 1; }
    void *buffer=NULL;
    if(posix_memalign(&buffer,4096,bytes)) { fprintf(stderr,"allocation failed\n"); return 1; }
    struct timespec t0,t1; size_t total=0;
    clock_gettime(CLOCK_MONOTONIC,&t0);
    regs[REG_CONTROL/4]=1u;
    while(total<bytes) {
        ssize_t got=read(cfd,(uint8_t*)buffer+total,bytes-total);
        if(got<0&&errno==EINTR) continue;
        if(got<=0) { perror("C2H read"); return 1; }
        total+=(size_t)got;
    }
    clock_gettime(CLOCK_MONOTONIC,&t1);

    size_t errors=0;
    if(mode==0) {
        const uint16_t *p=buffer;
        for(j=0;j<bytes/2;j++) if(p[j]>4095 && errors++<8)
            fprintf(stderr,"bad XADC sample[%zu]=0x%04x\n",j,p[j]);
    } else {
        const uint32_t *p=buffer; uint32_t expect=(mode==3&&seed==0)?0x1acebeef:seed;
        for(j=0;j<bytes/4;j++) {
            if(p[j]!=expect && errors++<8)
                fprintf(stderr,"mismatch[%zu]: got=%08x expected=%08x\n",j,p[j],expect);
            expect=(mode==3)?prbs_next(expect):expect+1;
        }
    }
    FILE *out=fopen(out_name,"wb");
    if(!out || fwrite(buffer,1,bytes,out)!=bytes) { perror(out_name); return 1; }
    fclose(out);
    double sec=elapsed(&t0,&t1);
    printf("mode=%s bytes=%zu time=%.6f s rate=%.2f MB/s errors=%zu status=0x%08x\n",
        mode_name,bytes,sec,bytes/sec/1e6,errors,regs[REG_STATUS/4]);
    free(buffer); close(cfd); munmap((void*)regs,4096); close(ufd);
    return errors?1:0;
}
