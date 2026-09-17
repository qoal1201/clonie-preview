"""Pinned Docling adapter. prepare downloads only public models; convert is offline."""
from pathlib import Path
import json
import os
import socket
import sys

ROOT = Path(sys.argv[2]).resolve()
os.environ.update(
    HF_HOME=str(ROOT / "hf"), DOCLING_CACHE_DIR=str(ROOT / "cache"),
    HF_HUB_DISABLE_TELEMETRY="1", DO_NOT_TRACK="1", ANONYMIZED_TELEMETRY="False",
    TOKENIZERS_PARALLELISM="false",
)

MODELS = {
    "docling-project/docling-layout-heron": "8f39ad3c0b4c58e9c2d2c84a38465abf757272d8",
    "docling-project/docling-models": "fc0f2d45e2218ea24bce5045f58a389aed16dc23",
}


def offline():
    os.environ.update(HF_HUB_OFFLINE="1", TRANSFORMERS_OFFLINE="1")

    def blocked(*args, **kwargs):
        raise RuntimeError("Network is disabled during document conversion")

    socket.socket.connect = blocked
    socket.socket.connect_ex = blocked
    socket.create_connection = blocked
    socket.getaddrinfo = blocked


def make_converter():
    from docling.datamodel.base_models import InputFormat
    from docling.datamodel.pipeline_options import PdfPipelineOptions, OcrMacOptions
    from docling.document_converter import DocumentConverter, PdfFormatOption

    options = PdfPipelineOptions(document_timeout=180, artifacts_path=ROOT / "models")
    options.ocr_options = OcrMacOptions(lang=["ko-KR", "en-US"])
    options.heading_hierarchy_options.enabled = True
    options.enable_remote_services = False
    options.allow_external_plugins = False
    return DocumentConverter(
        allowed_formats=[InputFormat.PDF, InputFormat.DOCX],
        format_options={InputFormat.PDF: PdfFormatOption(pipeline_options=options)},
    )


def prepare():
    from huggingface_hub import snapshot_download

    for repo, revision in MODELS.items():
        snapshot_download(repo_id=repo, revision=revision,
                          local_dir=ROOT / "models" / repo.replace("/", "--"))
    # Instantiate the full PDF pipeline offline. A ready marker means mandatory models
    # actually loaded, not merely that pip completed. No user document is opened here.
    offline()
    from docling.datamodel.base_models import InputFormat
    converter = make_converter()
    converter.initialize_pipeline(InputFormat.PDF)


def convert():
    offline()  # Before importing Docling, and before touching the document.
    from docling.datamodel.base_models import ConversionStatus
    from docling_core.types.doc.common.content_layer import ContentLayer

    source, target = Path(sys.argv[3]), Path(sys.argv[4])
    result = make_converter().convert(source, raises_on_error=False)
    if result.status not in (ConversionStatus.SUCCESS, ConversionStatus.PARTIAL_SUCCESS):
        raise RuntimeError("Document conversion failed")
    markdown = result.document.export_to_markdown(
        included_content_layers={ContentLayer.BODY, ContentLayer.FURNITURE},
    )
    if not markdown.strip():
        raise RuntimeError("No text found")
    partial = result.status == ConversionStatus.PARTIAL_SUCCESS or bool(result.errors)
    warnings = ["일부 내용을 읽지 못했습니다. 원본과 비교해 주세요."] if partial else []
    target.write_text(json.dumps(dict(markdown=markdown, partial=partial, warnings=warnings),
                                 ensure_ascii=False), encoding="utf-8")


if __name__ == "__main__":
    if sys.argv[1] == "prepare":
        prepare()
    elif sys.argv[1] == "convert":
        convert()
    else:
        raise SystemExit("Expected prepare or convert")
