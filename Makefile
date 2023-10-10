build:
	docker build . --tag pg
	docker run pg
