.PHONY: test clean

test:
	python scripts/run_sim.py

clean:
	python -c "import shutil; shutil.rmtree('build', ignore_errors=True)"
