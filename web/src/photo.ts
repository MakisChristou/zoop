import { withRequestDeadline } from "./request";
export const PHOTO_BYTES = 256 * 1024;
export type Crop = { x: number; y: number; zoom: number };
export const initialCrop: Crop = { x: 0.5, y: 0.5, zoom: 1 };
export const clamp = (n: number) => Math.max(0, Math.min(1, n));
export function cropRect(width: number, height: number, crop: Crop) {
  const size = Math.min(width, height) / Math.max(1, Math.min(3, crop.zoom));
  return {
    x: (width - size) * clamp(crop.x),
    y: (height - size) * clamp(crop.y),
    size,
  };
}
export function paintCrop(
  canvas: HTMLCanvasElement,
  photo: ImageBitmap,
  crop: Crop,
) {
  const ctx = canvas.getContext("2d");
  if (!ctx) throw new Error("Photo editing is unavailable in this browser.");
  const rect = cropRect(photo.width, photo.height, crop);
  ctx.fillStyle = "#ffffff";
  ctx.fillRect(0, 0, canvas.width, canvas.height);
  ctx.drawImage(
    photo,
    rect.x,
    rect.y,
    rect.size,
    rect.size,
    0,
    0,
    canvas.width,
    canvas.height,
  );
}
export async function cropJPEG(photo: ImageBitmap, crop: Crop) {
  const canvas = document.createElement("canvas");
  canvas.width = canvas.height = 512;
  paintCrop(canvas, photo, crop);
  for (const quality of [0.85, 0.7, 0.55]) {
    const blob = await new Promise<Blob | null>((resolve) =>
      canvas.toBlob(resolve, "image/jpeg", quality),
    );
    if (blob && blob.size <= PHOTO_BYTES) return blob;
  }
  throw new Error("Could not resize this photo. Choose another image.");
}
export async function photoRequest(
  path: string,
  signal: AbortSignal,
  body?: Blob,
) {
  return withRequestDeadline(signal, async (signal) => {
    const response = await fetch(path, {
      redirect: "error",
      method: body ? "PUT" : "GET",
      credentials: "same-origin",
      cache: "no-store",
      signal,
      headers: body ? { "Content-Type": "image/jpeg" } : undefined,
      body,
    });
    if (!body && response.status === 404) return null;
    if (!response.ok) {
      if (response.status === 401)
        window.dispatchEvent(new Event("zoop:unauthorized"));
      const error = await response.json().catch(() => null);
      throw new Error(
        error?.error?.message ?? "Could not save your photo. Try again.",
      );
    }
    const blob = await response.blob();
    if (blob.type !== "image/jpeg")
      throw new Error("Could not load your photo.");
    return blob;
  });
}
