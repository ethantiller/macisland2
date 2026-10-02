.PHONY: lint format bundle restart build-and-restart first-run doctor

lint:
	./scripts/lint.sh

format:
	./scripts/format.sh

bundle:
	./scripts/bundle.sh

restart:
	-pkill -x MacIsland
	open -n build/MacIsland.app

build-and-restart: bundle
	$(MAKE) restart

# Dev only: back to a first run (resets permissions, marks the install fresh, opens the guide). Run `make bundle` first.
first-run:
	./scripts/first-run.sh

# Prints the Mac, toolchain, checkout and built app, for working out why a build or launch fails.
doctor:
	./scripts/doctor.sh
