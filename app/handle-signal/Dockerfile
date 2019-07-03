# build stage
ARG GO_VERSION=1.12.6
FROM golang:${GO_VERSION}-alpine AS build-stage
RUN apk add --no-cache git
WORKDIR /src
COPY ./go.mod ./
RUN go mod download
COPY . .
RUN go build -o /goapp main.go

# production stage
FROM alpine:3.9
RUN apk add --no-cache dumb-init
ENTRYPOINT ["/usr/bin/dumb-init", "--rewrite", "15:3", "--"]
COPY --from=build-stage /goapp /
CMD ["/goapp"]
