package main

import (
	"bytes"
	"context"
	"encoding/binary"
	"fmt"
	"log"
	"net/http"
	os "os"
	"time"

	ocagent "contrib.go.opencensus.io/exporter/ocagent"
	"go.opencensus.io/plugin/ochttp"
	"go.opencensus.io/plugin/ochttp/propagation/tracecontext"
	"go.opencensus.io/trace"
)

func doWork(ctx context.Context) {
	_, span := trace.StartSpan(ctx, "doWork")
	defer span.End()

	fmt.Println("doing busy work")
	time.Sleep(80 * time.Millisecond)
	buf := bytes.NewBuffer([]byte{0xFF, 0x00, 0x00, 0x00})
	num, err := binary.ReadVarint(buf)
	if err != nil {
		span.SetStatus(trace.Status{
			Code:    trace.StatusCodeUnknown,
			Message: err.Error(),
		})
	}

	span.Annotate([]trace.Attribute{
		trace.Int64Attribute("bytes to int", num),
	}, "Invoking doWork")
	time.Sleep(20 * time.Millisecond)
}

func main() {
	// Register trace exporters to export the collected data.
	serviceName := os.Getenv("SERVICE_NAME")
	if len(serviceName) == 0 {
		serviceName = "go-app"
	}
	agentEndpoint := os.Getenv("OCAGENT_TRACE_EXPORTER_ENDPOINT")
	if len(agentEndpoint) == 0 {
		agentEndpoint = fmt.Sprintf("%s:%d", ocagent.DefaultAgentHost, ocagent.DefaultAgentPort)
	}

	exporter, err := ocagent.NewExporter(ocagent.WithInsecure(), ocagent.WithServiceName(serviceName), ocagent.WithAddress(agentEndpoint))
	if err != nil {
		log.Fatalf("Failed to create the agent exporter: %v", err)
	}

	trace.RegisterExporter(exporter)
	trace.ApplyConfig(trace.Config{DefaultSampler: trace.AlwaysSample()})

	client := &http.Client{Transport: &ochttp.Transport{Propagation: &tracecontext.HTTPFormat{}}}

	http.HandleFunc("/", func(w http.ResponseWriter, req *http.Request) {
		fmt.Fprintf(w, "hello world from %s", serviceName)

		ctx, span := trace.StartSpan(context.Background(), "main")
		defer span.End()

		for i := 0; i < 3; i++ {
			doWork(ctx)
		}

		targetService := os.Getenv("TARGET_SERVICE")
		if len(targetService) != 0 {
			targetServiceURI := fmt.Sprintf("http://%v", targetService)
			/*
				httpFormat := &tracecontext.HTTPFormat{}
				sc, ok := httpFormat.SpanContextFromRequest(req)
				if ok {
					_, span := trace.StartSpanWithRemoteParent(req.Context(), serviceName, sc)
					defer span.End()
				}
			*/

			r, _ := http.NewRequest("GET", targetServiceURI, nil)

			// Propagate the trace header info in the outgoing requests.
			r = r.WithContext(req.Context())
			resp, err := client.Do(r)
			if err != nil {
				log.Println(err)
			} else {
				// TODO: handle response
				resp.Body.Close()
			}
		}

	})

	http.HandleFunc("/healthz", func(w http.ResponseWriter, req *http.Request) {
		w.Write([]byte("ok"))
	})

	log.Println("We will listen :50030")
	log.Fatal(http.ListenAndServe(":50030", &ochttp.Handler{Propagation: &tracecontext.HTTPFormat{}}))
}
