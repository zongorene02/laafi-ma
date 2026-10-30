"""
Traçage distribué (OpenTelemetry -> Jaeger).

Le traçage donne à CHAQUE requête entrante un identifiant de "trace" et
mesure la durée de chacune de ses étapes. Jaeger (l'outil qui stocke et
affiche ces traces) permet ensuite de visualiser, pour UNE requête précise
(ex: une question vocale qui a mis 12 secondes), la chronologie complète —
une vue qu'aucun log pris isolément ne peut donner.
"""

from typing import Any

from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.sdk.resources import SERVICE_NAME, Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

from app.config import settings
from app.logging_config import get_logger

logger = get_logger(__name__)


def setup_tracing(app: Any) -> None:
    if not settings.tracing_enabled:
        logger.info("tracing.disabled")
        return

    resource = Resource(attributes={SERVICE_NAME: settings.service_name})
    provider = TracerProvider(resource=resource)
    exporter = OTLPSpanExporter(endpoint=settings.otel_exporter_endpoint, insecure=True)
    # BatchSpanProcessor : regroupe et envoie les traces par lots en
    # arrière-plan plutôt qu'une par une — évite qu'exporter une trace
    # ralentisse la requête qui vient de se terminer.
    provider.add_span_processor(BatchSpanProcessor(exporter))
    trace.set_tracer_provider(provider)

    # Instrumentation AUTOMATIQUE : une trace pour chaque requête HTTP
    # entrante, sans modifier le code métier.
    FastAPIInstrumentor.instrument_app(app)

    logger.info("tracing.enabled", endpoint=settings.otel_exporter_endpoint, service_name=settings.service_name)
