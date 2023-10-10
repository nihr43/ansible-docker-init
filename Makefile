build:
	docker build . --tag pg
	docker run -v $$(pwd)/vars.yml:/vars.yml:ro pg
