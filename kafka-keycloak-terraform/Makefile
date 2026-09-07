# Two-process deployment: network first, then apps.
#   make network ENV=dev
#   make apps    ENV=dev
#   make all     ENV=dev
#   make destroy ENV=dev   (apps first, then network)

ENV ?= dev
TF  ?= terraform

NET  = stacks/10-network
APPS = stacks/20-apps

.PHONY: init network network-plan apps apps-plan all destroy fmt validate

init:
	$(TF) -chdir=$(NET)  init
	$(TF) -chdir=$(APPS) init

network-plan:
	$(TF) -chdir=$(NET) plan -var-file=$(ENV).tfvars

network:
	$(TF) -chdir=$(NET) apply -var-file=$(ENV).tfvars

apps-plan:
	$(TF) -chdir=$(APPS) plan -var-file=$(ENV).tfvars

apps:
	$(TF) -chdir=$(APPS) apply -var-file=$(ENV).tfvars

all: network apps

destroy:
	$(TF) -chdir=$(APPS) destroy -var-file=$(ENV).tfvars
	$(TF) -chdir=$(NET)  destroy -var-file=$(ENV).tfvars

fmt:
	$(TF) fmt -recursive

validate: init
	$(TF) -chdir=$(NET)  validate
	$(TF) -chdir=$(APPS) validate
