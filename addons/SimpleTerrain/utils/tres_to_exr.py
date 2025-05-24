#!/usr/bin/env python3
import re
import sys
import numpy as np
import OpenEXR, Imath

# Can be used to convert a RFLOAT .tres heightmap file to a .exr file to edit the heightmap in an image editor like GIMP.
# Needs: pip install numpy OpenEXR Imath

def extract_rfloat_from_tres(path):
	with open(path, "r") as f:
		text = f.read()

	# find width & height
	w_m = re.search(r'"width":\s*(\d+)', text)
	h_m = re.search(r'"height":\s*(\d+)', text)
	if not w_m or not h_m:
		raise ValueError("Width/height not found in .tres")
	width = int(w_m.group(1))
	height = int(h_m.group(1))

	# capture everything inside the PackedByteArray(...)
	m = re.search(r'PackedByteArray\((.*?)\)', text, re.DOTALL)
	if not m:
		raise ValueError("PackedByteArray data not found")
	data_str = m.group(1)

	# parse bytes
	byte_values = [int(v) for v in data_str.split(",") if v.strip().isdigit()]
	buf = bytes(byte_values)

	# to float32 array
	arr = np.frombuffer(buf, dtype=np.float32)
	if arr.size != width * height:
		raise ValueError(f"Data size mismatch: expected {width*height}, got {arr.size}")
	return arr.reshape((height, width))

def save_exr(img, path):
	# single‐channel float EXR
	h, w = img.shape
	header = OpenEXR.Header(w, h)
	header['channels'] = {'R': Imath.Channel(Imath.PixelType(Imath.PixelType.FLOAT))}
	exr = OpenEXR.OutputFile(path, header)
	exr.writePixels({'R': img.astype(np.float32).tobytes()})
	exr.close()

if __name__ == "__main__":
	if len(sys.argv) != 3:
		print("Usage: python tres_to_exr.py input.tres output.exr")
		sys.exit(1)

	input_tres, output_exr = sys.argv[1], sys.argv[2]
	img = extract_rfloat_from_tres(input_tres)
	save_exr(img, output_exr)
	print(f"Saved EXR to {output_exr}")
