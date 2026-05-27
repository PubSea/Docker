"""Send sample logs, metrics, and traces to Alloy via OTLP HTTP."""

import time

from opentelemetry import metrics, trace
from opentelemetry._logs import set_logger_provider
from opentelemetry.exporter.otlp.proto.http._log_exporter import OTLPLogExporter
from opentelemetry.exporter.otlp.proto.http.metric_exporter import OTLPMetricExporter
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk._logs import LoggerProvider, LoggingHandler
from opentelemetry.sdk._logs.export import BatchLogRecordProcessor
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
import logging

ENDPOINT = "http://alloy:4318"
RESOURCE = Resource.create(
    {
        "service.name": "lgtm-test",
        "service.instance.id": "demo-1",
        "deployment.environment": "local",
    }
)


def send_logs() -> None:
    exporter = OTLPLogExporter(endpoint=f"{ENDPOINT}/v1/logs")
    provider = LoggerProvider(resource=RESOURCE)
    provider.add_log_record_processor(BatchLogRecordProcessor(exporter))
    set_logger_provider(provider)

    handler = LoggingHandler(level=logging.INFO, logger_provider=provider)
    logger = logging.getLogger("lgtm.test")
    logger.setLevel(logging.INFO)
    logger.addHandler(handler)

    for i in range(5):
        logger.info("LGTM stack test log %s", i, extra={"event": "demo", "iteration": i})
        time.sleep(0.2)

    provider.force_flush()
    provider.shutdown()


def send_metrics() -> None:
    reader = PeriodicExportingMetricReader(
        OTLPMetricExporter(endpoint=f"{ENDPOINT}/v1/metrics"),
        export_interval_millis=1000,
    )
    provider = MeterProvider(resource=RESOURCE, metric_readers=[reader])
    metrics.set_meter_provider(provider)
    meter = metrics.get_meter("lgtm.test")

    counter = meter.create_counter("lgtm_test_requests_total", description="Demo counter")
    histogram = meter.create_histogram(
        "lgtm_test_duration_seconds", description="Demo latency", unit="s"
    )

    for i in range(10):
        counter.add(1, {"route": "/demo", "status": "ok"})
        histogram.record(0.05 + (i * 0.01), {"route": "/demo"})
        time.sleep(0.3)

    provider.force_flush()
    provider.shutdown()


def send_traces() -> None:
    exporter = OTLPSpanExporter(endpoint=f"{ENDPOINT}/v1/traces")
    provider = TracerProvider(resource=RESOURCE)
    provider.add_span_processor(BatchSpanProcessor(exporter))
    trace.set_tracer_provider(provider)
    tracer = trace.get_tracer("lgtm.test")

    for i in range(3):
        with tracer.start_as_current_span("demo-request", attributes={"iteration": i}) as span:
            span.add_event("processing")
            with tracer.start_as_current_span("demo-db-query"):
                time.sleep(0.1)
        time.sleep(0.2)

    provider.force_flush()
    provider.shutdown()


if __name__ == "__main__":
    print(f"Sending OTLP test data to {ENDPOINT} ...")
    send_logs()
    print("Logs sent.")
    send_metrics()
    print("Metrics sent.")
    send_traces()
    print("Traces sent.")
    print("Done.")
