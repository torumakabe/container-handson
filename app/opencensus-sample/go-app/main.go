package main

import (
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

		targetService := os.Getenv("TARGET_SERVICE")
		if len(targetService) != 0 {
			targetServiceURI := fmt.Sprintf("http://%v", targetService)

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
		time.Sleep(20 * time.Millisecond)

	})

	http.HandleFunc("/healthz", func(w http.ResponseWriter, req *http.Request) {
		w.Write([]byte("ok"))
	})

	log.Println("We will listen :50030")
	log.Fatal(http.ListenAndServe(":50030", &ochttp.Handler{Propagation: &tracecontext.HTTPFormat{}}))
}
