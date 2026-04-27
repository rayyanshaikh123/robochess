"""Quick diagnostic: test detection counts only."""
try:
    from backend.board_recognizer import BoardRecognizer
except ImportError:
    from board_recognizer import BoardRecognizer
import cv2, glob

br = BoardRecognizer("models/best.pt", confidence=0.01)

for img_path in glob.glob("datasets/train/images/*.jpg")[:3]:
    img = cv2.imread(img_path)
    if img is None: continue
    dets = br.detect(img)
    print(f"TRAIN conf=0.01: {len(dets)} dets")

br2 = BoardRecognizer("models/best.pt", confidence=0.35)
for img_path in glob.glob("datasets/train/images/*.jpg")[:3]:
    img = cv2.imread(img_path)
    if img is None: continue
    dets = br2.detect(img)
    print(f"TRAIN conf=0.35: {len(dets)} dets")

# Test by saving a frame from camera with very low conf
print("CLASSES:", list(br.model.names.values()))
