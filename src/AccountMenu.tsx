import { useEffect, useRef, useState, type PointerEvent } from "react";
import { Camera, LogOut, Shield, LoaderCircle, X, Share2 } from "lucide-react";
import { endpoint, type Account } from "./data";
import {
  clamp,
  cropJPEG,
  cropRect,
  initialCrop,
  paintCrop,
  photoRequest,
  type Crop,
} from "./photo";

export function AccountMenu({
  account,
  device,
  signingOut,
  logout,
}: {
  account: Account;
  device?: string;
  signingOut: boolean;
  logout: () => void;
}) {
  const [menu, setMenu] = useState(false),
    [editing, setEditing] = useState(false);
  const [photo, setPhoto] = useState<Blob | null>(null),
    [url, setURL] = useState("");
  const trigger = useRef<HTMLButtonElement>(null);
  const photoRead = useRef<AbortController | null>(null);
  useEffect(() => {
    if (!device) return;
    const controller = new AbortController();
    photoRead.current = controller;
    photoRequest(endpoint(device, "profile/photo"), controller.signal)
      .then((blob) => {
        if (!controller.signal.aborted) setPhoto(blob);
      })
      .catch(() => {});
    return () => controller.abort();
  }, [device]);
  useEffect(() => {
    if (!photo) return;
    const next = URL.createObjectURL(photo);
    setURL(next);
    return () => URL.revokeObjectURL(next);
  }, [photo]);
  useEffect(() => {
    const close = () => setMenu(false);
    window.addEventListener("hashchange", close);
    return () => window.removeEventListener("hashchange", close);
  }, []);
  const wasEditing = useRef(false);
  useEffect(() => {
    if (!editing && wasEditing.current) trigger.current?.focus();
    wasEditing.current = editing;
  }, [editing]);
  const closeEditor = () => setEditing(false);
  return (
    <div className="account">
      <button
        ref={trigger}
        className="avatar"
        aria-label="Account menu"
        aria-expanded={menu}
        onClick={() => setMenu(!menu)}
      >
        {url ? (
          <img src={url} alt="" />
        ) : (
          account.email.slice(0, 2).toUpperCase()
        )}
      </button>
      {menu && (
        <div className="menu">
          <span className="email">{account.email}</span>
          {device && (
            <button
              onClick={() => {
                setMenu(false);
                setEditing(true);
              }}
            >
              <Camera size={16} /> Profile photo
            </button>
          )}
          <a href="#Shares" onClick={() => setMenu(false)}>
            <Share2 size={16} /> Shared dashboards
          </a>
          {account.is_admin && (
            <a href="#Admin" onClick={() => setMenu(false)}>
              <Shield size={16} /> Admin
            </a>
          )}
          <button onClick={logout} disabled={signingOut}>
            {signingOut ? (
              <LoaderCircle className="spinner" size={16} />
            ) : (
              <LogOut size={16} />
            )}{" "}
            Sign out
          </button>
        </div>
      )}
      {editing && device && (
        <PhotoEditor
          device={device}
          current={url}
          onClose={closeEditor}
          onSave={(blob) => {
            photoRead.current?.abort();
            setPhoto(blob);
            closeEditor();
          }}
        />
      )}
    </div>
  );
}

function PhotoEditor({
  device,
  current,
  onClose,
  onSave,
}: {
  device: string;
  current: string;
  onClose: () => void;
  onSave: (blob: Blob) => void;
}) {
  const dialog = useRef<HTMLDialogElement>(null),
    canvas = useRef<HTMLCanvasElement>(null),
    file = useRef<HTMLInputElement>(null);
  const [photo, setPhoto] = useState<ImageBitmap | null>(null),
    [crop, setCrop] = useState<Crop>(initialCrop);
  const [loading, setLoading] = useState(false),
    [saving, setSaving] = useState(false),
    [error, setError] = useState("");
  const controller = useRef(new AbortController()),
    generation = useRef(0);
  const drag = useRef<{ x: number; y: number; crop: Crop } | null>(null);
  useEffect(() => {
    controller.current = new AbortController();
    dialog.current?.showModal();
    return () => {
      generation.current++;
      controller.current.abort();
      dialog.current?.close();
    };
  }, []);
  useEffect(() => () => photo?.close(), [photo]);
  useEffect(() => {
    if (canvas.current && photo) paintCrop(canvas.current, photo, crop);
  }, [photo, crop]);
  async function choose(selected?: File) {
    if (!selected) return;
    setError("");
    if (!["image/jpeg", "image/png", "image/webp"].includes(selected.type)) {
      setError("Choose a JPEG, PNG or WebP photo.");
      return;
    }
    if (selected.size > 20 * 1024 * 1024) {
      setError("Choose a photo smaller than 20 MB.");
      return;
    }
    const id = ++generation.current;
    setLoading(true);
    try {
      const image = await createImageBitmap(selected);
      if (id !== generation.current) {
        image.close();
        return;
      }
      if (image.width * image.height > 80_000_000) {
        image.close();
        throw new Error();
      }
      setPhoto(image);
      setCrop(initialCrop);
    } catch {
      if (id === generation.current)
        setError("Could not open this photo. Choose another image.");
    } finally {
      if (id === generation.current) setLoading(false);
    }
  }
  function move(e: PointerEvent<HTMLCanvasElement>) {
    if (!drag.current || !photo || saving || loading) return;
    const start = drag.current,
      rect = cropRect(photo.width, photo.height, start.crop);
    const scale = rect.size / e.currentTarget.getBoundingClientRect().width;
    setCrop({
      ...start.crop,
      x:
        photo.width === rect.size
          ? 0.5
          : clamp(
              start.crop.x -
                ((e.clientX - start.x) * scale) / (photo.width - rect.size),
            ),
      y:
        photo.height === rect.size
          ? 0.5
          : clamp(
              start.crop.y -
                ((e.clientY - start.y) * scale) / (photo.height - rect.size),
            ),
    });
  }
  async function save() {
    if (!photo || saving || loading) return;
    setSaving(true);
    setError("");
    try {
      const jpeg = await cropJPEG(photo, crop);
      if (controller.current.signal.aborted) return;
      const saved = await photoRequest(
        endpoint(device, "profile/photo"),
        controller.current.signal,
        jpeg,
      );
      if (saved && !controller.current.signal.aborted) onSave(saved);
    } catch (e) {
      if (!controller.current.signal.aborted) setError((e as Error).message);
    } finally {
      if (!controller.current.signal.aborted) setSaving(false);
    }
  }
  return (
    <dialog
      ref={dialog}
      className="goal-dialog photo-dialog"
      aria-label="Profile photo"
      onCancel={(e) => {
        e.preventDefault();
        if (!saving) onClose();
      }}
    >
      <header>
        <h2>Profile photo</h2>
        <button aria-label="Close" disabled={saving} onClick={onClose}>
          <X size={18} />
        </button>
      </header>
      <div className="photo-preview" aria-busy={loading}>
        {photo ? (
          <canvas
            ref={canvas}
            width={512}
            height={512}
            tabIndex={0}
            aria-label="Photo crop"
            aria-description="Use arrow keys to reposition the photo. Use the Zoom slider to resize."
            onKeyDown={(e) => {
              if (saving) return;
              if (
                ["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown"].includes(
                  e.key,
                )
              ) {
                e.preventDefault();
                setCrop((c) => ({
                  ...c,
                  x: clamp(
                    c.x +
                      (e.key === "ArrowLeft"
                        ? -0.03
                        : e.key === "ArrowRight"
                          ? 0.03
                          : 0),
                  ),
                  y: clamp(
                    c.y +
                      (e.key === "ArrowUp"
                        ? -0.03
                        : e.key === "ArrowDown"
                          ? 0.03
                          : 0),
                  ),
                }));
              }
            }}
            onPointerDown={(e) => {
              if (saving) return;
              e.currentTarget.setPointerCapture(e.pointerId);
              drag.current = { x: e.clientX, y: e.clientY, crop };
            }}
            onPointerMove={move}
            onPointerUp={() => {
              drag.current = null;
            }}
            onPointerCancel={() => {
              drag.current = null;
            }}
          />
        ) : current ? (
          <img src={current} alt="Current profile photo" />
        ) : (
          <Camera size={48} aria-hidden="true" />
        )}
      </div>
      {loading && (
        <p role="status">
          <LoaderCircle className="spinner" size={16} /> Opening photo…
        </p>
      )}
      {photo && (
        <label className="photo-zoom">
          Zoom
          <input
            type="range"
            min="1"
            max="3"
            step="0.01"
            value={crop.zoom}
            disabled={saving || loading}
            onChange={(e) =>
              setCrop((c) => ({ ...c, zoom: Number(e.target.value) }))
            }
          />
        </label>
      )}
      {error && (
        <p role="alert" className="error">
          {error}
        </p>
      )}
      <input
        ref={file}
        type="file"
        accept="image/jpeg,image/png,image/webp"
        aria-label="Choose photo file"
        hidden
        onChange={(e) => {
          void choose(e.target.files?.[0]);
          e.target.value = "";
        }}
      />
      <footer>
        <button
          disabled={saving || loading}
          onClick={() => file.current?.click()}
        >
          Choose photo
        </button>
        {photo && (
          <button
            className="primary"
            disabled={saving || loading}
            onClick={save}
          >
            {saving && <LoaderCircle className="spinner" size={16} />}{" "}
            {saving ? "Saving…" : "Save"}
          </button>
        )}
      </footer>
    </dialog>
  );
}
