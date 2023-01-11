FROM node:alpine

ENTRYPOINT ["/usr/src/app/docker-entrypoint.sh"]

WORKDIR /usr/src/app

ENV FOLIO_REGISTRY='http://folio-registry.aws.indexdata.com'

RUN apk add bash curl

COPY docker-entrypoint.sh .

