.PHONY: test vivado-project bitstream clean

VIVADO ?= vivado

test:
	python scripts/run_sim.py

vivado-project:
	$(VIVADO) -mode batch -source fpga/kc705/tcl/create_project.tcl

bitstream:
	$(VIVADO) -mode batch -source fpga/kc705/tcl/build_bitstream.tcl

clean:
	python -c "import shutil; shutil.rmtree('build', ignore_errors=True)"
