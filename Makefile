# Each target runs one script in lib/, so `make build` and `bash lib/build.sh` are the same.

.DEFAULT_GOAL := help

.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Image
.PHONY: guard
guard: ## Print whether the pinned inputs differ from the newest release. FORCE=true always says yes.
	bash lib/should_build.sh

.PHONY: build
build: ## Build every platform without pushing, to prove the Dockerfile still works. Needs buildx.
	bash lib/build.sh

.PHONY: publish
publish: ## Build and push the manifest list to GHCR, and stage the release assets. Needs GHCR_TOKEN.
	bash lib/publish.sh

.PHONY: release
release: ## Create the GitHub release from the staged assets. Run after publish. Needs gh.
	bash lib/release.sh

##@ Housekeeping
.PHONY: clean
clean: ## Remove the staged release assets.
	rm -rf .cache
