# Template Operator v2 docs
#
# Targets here are for local development tasks that aren't run by the docs
# build pipeline (which lives in .github/workflows/). The build pipeline runs
# inside containers based on Dockerfile / DockerfileLocal.

OPERATOR_REPO         ?= https://github.com/stakater-ab/template-operator-v2.git
OPERATOR_REF          ?= main
WORK_DIR              ?= .work
LOCALBIN              ?= $(WORK_DIR)/bin

CRD_REF_DOCS          ?= $(LOCALBIN)/crd-ref-docs
CRD_REF_DOCS_VERSION  ?= v0.3.0

.PHONY: help
help: ## Show this help.
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.PHONY: api-reference
api-reference: crd-ref-docs $(WORK_DIR)/operator/api/v2alpha1 ## Generate content/reference/api.md from the operator Go source.
	$(CRD_REF_DOCS) \
		--source-path=$(WORK_DIR)/operator/api/v2alpha1 \
		--config=crd-ref-docs.yaml \
		--templates-dir=crd-ref-templates \
		--renderer=markdown \
		--output-path=content/reference/api.md
	@sed -i 's|\[AllowDeny\](#allowdeny)|AllowDeny|g' content/reference/api.md
	@echo "Wrote content/reference/api.md (OPERATOR_REF=$(OPERATOR_REF))"

.PHONY: crd-ref-docs
crd-ref-docs: $(CRD_REF_DOCS) ## Download crd-ref-docs locally if necessary.
$(CRD_REF_DOCS): $(LOCALBIN)
	$(call go-install-tool,$(CRD_REF_DOCS),github.com/elastic/crd-ref-docs,$(CRD_REF_DOCS_VERSION))

$(LOCALBIN):
	@mkdir -p $(LOCALBIN)

# go-install-tool will `go install` any package with a custom target and binary name, pinned to a version.
# $1 - target path with name of binary
# $2 - package url which can be installed
# $3 - specific version of package
define go-install-tool
@[ -f "$(1)-$(3)" ] || { \
set -e; \
package=$(2)@$(3) ;\
echo "Downloading $${package}" ;\
rm -f $(1) || true ;\
GOBIN=$(abspath $(LOCALBIN)) go install $${package} ;\
mv $(1) $(1)-$(3) ;\
} ;\
ln -sf $(notdir $(1))-$(3) $(1)
endef

$(WORK_DIR)/operator/api/v2alpha1:
	@mkdir -p $(WORK_DIR)
	@if [ -d "$(WORK_DIR)/operator/.git" ]; then \
		cd $(WORK_DIR)/operator && git fetch origin $(OPERATOR_REF) && git checkout $(OPERATOR_REF) && git reset --hard origin/$(OPERATOR_REF); \
	else \
		git clone --depth=20 --branch $(OPERATOR_REF) $(OPERATOR_REPO) $(WORK_DIR)/operator; \
	fi

.PHONY: clean
clean: ## Remove the work directory used by api-reference.
	rm -rf $(WORK_DIR)
