"""
Train YOLO11n for chess piece detection.

Usage:
    python train_model.py                     # default: 100 epochs, batch 16
    python train_model.py --balanced          # CPU-friendly strong (yolo11m, 960 imgsz, 150 epochs)
    python train_model.py --large             # high-accuracy preset (yolo11l, 1280 imgsz)
    python train_model.py --xlarge            # maximum-accuracy preset (yolo11x, longer train)
    python train_model.py --gpu-max           # GPU-first maximum-accuracy preset
    python train_model.py --epochs 50         # custom epochs
    python train_model.py --epochs 1 --batch 4  # quick smoke test
    python train_model.py --resume            # resume from last checkpoint
"""

import argparse
from pathlib import Path
from ultralytics import YOLO

try:
    import torch
except Exception:
    torch = None


def _is_cuda_request(device_value):
    """Return True if the user requested a CUDA-like device string."""
    if device_value is None:
        return False
    text = str(device_value).strip().lower()
    if not text or text == "auto":
        return False
    if text in {"cpu", "mps"}:
        return False
    if text.startswith("cuda"):
        return True
    return any(ch.isdigit() for ch in text)


def resolve_training_device(device_value, strict_device=False):
    """Resolve a safe Ultralytics device value for the current machine."""
    if device_value is None:
        return "0" if torch and torch.cuda.is_available() else "cpu"

    requested = str(device_value).strip()
    if not requested or requested.lower() == "auto":
        return "0" if torch and torch.cuda.is_available() else "cpu"

    if _is_cuda_request(requested):
        cuda_available = bool(torch and torch.cuda.is_available())
        if not cuda_available:
            msg = (
                f"[WARN] Requested device='{requested}', but CUDA is not available in this environment. "
                "Falling back to CPU."
            )
            if strict_device:
                raise ValueError(msg + " Re-run with --device cpu or remove --strict-device.")
            print(msg)
            return "cpu"

    return requested


def get_cuda_memory_gb():
    """Return total GPU memory in GiB for device 0, or None if unavailable."""
    if not torch or not torch.cuda.is_available():
        return None
    try:
        props = torch.cuda.get_device_properties(0)
        return props.total_memory / (1024 ** 3)
    except Exception:
        return None


def is_cuda_oom(error):
    """Best-effort detection for CUDA out-of-memory failures."""
    message = str(error).lower()
    return "cuda out of memory" in message or "out of memory" in message


def build_training_attempts(args):
    """Build a list of training configurations from strongest to safest."""
    attempts = [
        {
            "label": "primary",
            "batch": args.batch,
            "imgsz": args.imgsz,
            "workers": args.workers,
            "cache": args.cache,
            "close_mosaic": args.close_mosaic,
        }
    ]

    if args.gpu_max or args.xlarge:
        cuda_memory_gb = get_cuda_memory_gb()
        if cuda_memory_gb is not None and cuda_memory_gb < 10:
            first_retry = 1024 if args.imgsz > 1024 else max(960, args.imgsz)
            attempts.extend(
                [
                    {
                        "label": f"retry-1 ({cuda_memory_gb:.1f} GiB VRAM)",
                        "batch": min(args.batch, 2),
                        "imgsz": first_retry,
                        "workers": 2,
                        "cache": False,
                        "close_mosaic": min(args.close_mosaic, 10),
                    },
                    {
                        "label": "retry-2",
                        "batch": 1,
                        "imgsz": 960,
                        "workers": 0,
                        "cache": False,
                        "close_mosaic": 10,
                    },
                ]
            )
        else:
            attempts.extend(
                [
                    {
                        "label": "retry-1",
                        "batch": max(2, min(args.batch, 2)),
                        "imgsz": 1024 if args.imgsz > 1024 else args.imgsz,
                        "workers": min(args.workers, 2),
                        "cache": False,
                        "close_mosaic": min(args.close_mosaic, 10),
                    },
                    {
                        "label": "retry-2",
                        "batch": 2,
                        "imgsz": 960,
                        "workers": 0,
                        "cache": False,
                        "close_mosaic": 10,
                    },
                ]
            )

    return attempts


def main():
    parser = argparse.ArgumentParser(description="Train YOLO11n for chess piece detection")
    parser.add_argument("--model", default="yolo11n.pt", help="Base model to fine-tune (default: yolo11n.pt)")
    parser.add_argument("--data", default="data.yaml", help="Path to data.yaml")
    parser.add_argument("--epochs", type=int, default=100, help="Number of training epochs")
    parser.add_argument("--batch", type=int, default=16, help="Batch size")
    parser.add_argument("--imgsz", type=int, default=640, help="Image size for training")
    parser.add_argument(
        "--balanced",
        action="store_true",
        help=(
            "CPU-friendly strong preset: model=yolo11m.pt, epochs=150, imgsz=960, "
            "batch=6, workers=1, no-cache (good quality without resource spam)"
        ),
    )
    parser.add_argument(
        "--large",
        action="store_true",
        help=(
            "High-accuracy preset: model=yolo11l.pt, epochs=200, imgsz=1280, "
            "batch=8 (can still override with explicit flags)"
        ),
    )
    parser.add_argument(
        "--xlarge",
        action="store_true",
        help=(
            "Maximum-accuracy preset: model=yolo11x.pt, epochs=400, imgsz=1280, "
            "batch=4, patience=80, cos_lr=True, cache=True"
        ),
    )
    parser.add_argument(
        "--gpu-max",
        action="store_true",
        help=(
            "GPU-first maximum-accuracy preset: model=yolo11x.pt, epochs=400, imgsz=1280, "
            "batch=4, patience=100, cos_lr=True, cache=True"
        ),
    )
    parser.add_argument("--device", default=None, help="Device: 'cpu', '0' (GPU 0), etc. Auto-detected if omitted")
    parser.add_argument(
        "--strict-device",
        action="store_true",
        help="Fail instead of falling back to CPU when requested device is unavailable",
    )
    parser.add_argument("--patience", type=int, default=20, help="Early stopping patience")
    parser.add_argument("--workers", type=int, default=8, help="Data loader workers")
    parser.add_argument("--cache", action="store_true", help="Cache dataset in RAM for faster training")
    parser.add_argument("--cos-lr", action="store_true", help="Use cosine learning-rate schedule")
    parser.add_argument("--close-mosaic", type=int, default=10, help="Disable mosaic in final N epochs")
    parser.add_argument("--resume", action="store_true", help="Resume training from last checkpoint")
    parser.add_argument("--project", default="runs/chess", help="Project directory for saving results")
    parser.add_argument("--name", default="train", help="Run name")
    args = parser.parse_args()

    args.device = resolve_training_device(args.device, strict_device=args.strict_device)

    if args.balanced:
        # Strong quality with CPU-friendly settings: reduce image size, workers, caching.
        if args.model == "yolo11n.pt":
            args.model = "yolo11m.pt"
        if args.epochs == 100:
            args.epochs = 150
        if args.batch == 16:
            args.batch = 6
        if args.imgsz == 640:
            args.imgsz = 960
        if args.workers == 8:
            args.workers = 1
        args.cache = False  # Disable RAM caching to avoid memory pressure
        if args.name == "train":
            args.name = "train_balanced"

    if args.large:
        # High-capacity baseline for better detection quality.
        if args.model == "yolo11n.pt":
            args.model = "yolo11l.pt"
        if args.epochs == 100:
            args.epochs = 200
        if args.batch == 16:
            args.batch = 8
        if args.imgsz == 640:
            args.imgsz = 1280
        if args.name == "train":
            args.name = "train_large"

    if args.xlarge or args.gpu_max:
        # Strongest preset aimed at best quality for piece detection.
        if args.model == "yolo11n.pt":
            args.model = "yolo11x.pt"
        if args.epochs == 100:
            args.epochs = 400
        if args.batch == 16:
            args.batch = 4
        if args.imgsz == 640:
            args.imgsz = 1280
        if args.patience == 20:
            args.patience = 100
        if args.workers == 8:
            args.workers = 4
        args.cos_lr = True
        args.cache = True
        if args.gpu_max:
            cuda_memory_gb = get_cuda_memory_gb()
            if cuda_memory_gb is not None and cuda_memory_gb < 10:
                args.batch = min(args.batch, 2)
                args.imgsz = 1024
                args.workers = min(args.workers, 2)
                args.cache = False
                if args.close_mosaic == 10:
                    args.close_mosaic = 10
            elif cuda_memory_gb is not None and cuda_memory_gb < 12:
                args.batch = min(args.batch, 2)
                args.imgsz = 1024 if args.imgsz > 1024 else args.imgsz
                args.workers = min(args.workers, 2)
            if args.close_mosaic == 10:
                args.close_mosaic = 15
            if args.name == "train":
                args.name = "train_gpu_max"
        elif args.name == "train":
            args.name = "train_xlarge"

    ROOT = Path(__file__).parent.resolve()
    data_path = ROOT / args.data

    if not data_path.exists():
        print(f"[ERROR] data.yaml not found at {data_path}")
        return

    # Ensure output model directory exists
    models_dir = ROOT / "models"
    models_dir.mkdir(exist_ok=True)

    print("=" * 60)
    print("  Chess Piece Detection — YOLO Training")
    print("=" * 60)
    print(f"  Data config : {data_path}")
    print(f"  Base model  : {args.model}")
    print(f"  Epochs      : {args.epochs}")
    print(f"  Batch size  : {args.batch}")
    print(f"  Image size  : {args.imgsz}")
    print(f"  Device      : {args.device}")
    print(f"  Patience    : {args.patience}")
    print(f"  Workers     : {args.workers}")
    print(f"  Cache       : {args.cache}")
    print(f"  Cosine LR   : {args.cos_lr}")
    print(f"  CloseMosaic : {args.close_mosaic}")
    print(f"  Output dir  : {args.project}/{args.name}")
    print("=" * 60)

    # Load model
    if args.resume:
        # Resume from last checkpoint. Try multiple common YOLO project structures.
        candidates = [
            ROOT / args.project / args.name / "weights" / "last.pt",
            ROOT / args.project / "detect" / args.name / "weights" / "last.pt",
            ROOT / "detect" / args.project / args.name / "weights" / "last.pt",
            ROOT / "runs" / "detect" / args.project / args.name / "weights" / "last.pt",
            ROOT / "runs" / "detect" / args.name / "weights" / "last.pt",
            Path(args.project) / args.name / "weights" / "last.pt",
        ]
        
        found_cands = [c for c in candidates if c.exists()]
        if not found_cands:
            print(f"[ERROR] No checkpoint found. Checked locations:")
            for cand in candidates:
                print(f"  - {cand}")
            return
        
        # Sort by modification time (newest first)
        found_cands.sort(key=lambda x: x.stat().st_mtime, reverse=True)
        last_ckpt = found_cands[0]

        model = YOLO(str(last_ckpt))
        print(f"[OK] Resuming from {last_ckpt}")
    else:
        model = YOLO(args.model)
        print(f"[OK] Loaded base model: {args.model}")

    # Train with automatic backoff for CUDA OOM.
    results = None
    training_error = None
    attempt_list = build_training_attempts(args)

    for attempt_index, attempt in enumerate(attempt_list, start=1):
        print(
            f"[INFO] Training attempt {attempt_index}/{len(attempt_list)}: "
            f"batch={attempt['batch']}, imgsz={attempt['imgsz']}, workers={attempt['workers']}, "
            f"cache={attempt['cache']}, close_mosaic={attempt['close_mosaic']}"
        )
        try:
            results = model.train(
                data=str(data_path),
                epochs=args.epochs,
                batch=attempt["batch"],
                imgsz=attempt["imgsz"],
                device=args.device,
                project=args.project,
                name=args.name,
                resume=args.resume,
                exist_ok=True,
                seed=42,
                patience=args.patience,
                workers=attempt["workers"],
                cache=attempt["cache"],
                cos_lr=args.cos_lr,
                close_mosaic=attempt["close_mosaic"],
                save=True,
                verbose=True,
            )
            training_error = None
            break
        except RuntimeError as error:
            training_error = error
            if not is_cuda_oom(error) or attempt_index == len(attempt_list):
                raise
            print(
                f"[WARN] CUDA OOM on attempt {attempt_index}; retrying with a smaller GPU footprint."
            )
            if torch and torch.cuda.is_available():
                torch.cuda.empty_cache()

    if results is None:
        raise training_error

    # Copy best weights to models/best.pt for easy server use
    # Use the actual save_dir from results (YOLO may nest paths unpredictably)
    import shutil

    best_dst = models_dir / "best.pt"
    save_dir = Path(results.save_dir) if hasattr(results, 'save_dir') else None
    best_src = save_dir / "weights" / "best.pt" if save_dir else None

    # Fallback: search common locations if save_dir doesn't work
    if best_src is None or not best_src.exists():
        candidates = [
            ROOT / args.project / args.name / "weights" / "best.pt",
            ROOT / "runs" / "detect" / args.project / args.name / "weights" / "best.pt",
            ROOT / "runs" / "detect" / "runs" / "chess" / args.name / "weights" / "best.pt",
        ]
        for candidate in candidates:
            if candidate.exists():
                best_src = candidate
                break

    if best_src and best_src.exists():
        shutil.copy2(str(best_src), str(best_dst))
        print(f"\n[OK] Best model copied to {best_dst}")
        print(f"     (source: {best_src})")
    else:
        print(f"\n[WARN] best.pt not found. Search locations:")
        if save_dir:
            print(f"  - {save_dir / 'weights' / 'best.pt'}")
        for c in candidates:
            print(f"  - {c}")
        print(f"  Please manually copy best.pt to {best_dst}")

    print(f"\n[DONE] Training complete.")
    print(f"  Best model destination: {best_dst}")


if __name__ == "__main__":
    main()
