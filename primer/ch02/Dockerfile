# build stage
ARG GO_VERSION=1.11.1
FROM golang:${GO_VERSION}-alpine AS build-stage
WORKDIR /tmp
COPY ./ /tmp
RUN go build -o main main.go

# production stage
FROM alpine:3.8
WORKDIR /root/
COPY --from=build-stage /tmp/main .
EXPOSE 80
CMD ["./main"]