.PHONY: lint format bundle restart build-and-restart

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