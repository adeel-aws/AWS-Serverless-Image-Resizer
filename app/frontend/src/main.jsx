import { useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import './styles.css';

const MAX_FILE_SIZE = 8 * 1024 * 1024;
const supportedTypes = ['image/jpeg', 'image/png', 'image/webp'];

function Icon({ name, size = 20 }) {
  const paths = {
    image: <><rect x="3" y="4" width="18" height="16" rx="2" /><circle cx="8.5" cy="9" r="1.5" /><path d="m21 15-4.2-4.2L6 21" /></>,
    upload: <><path d="M12 16V3" /><path d="m7 8 5-5 5 5" /><path d="M5 21h14" /></>,
    spark: <path d="m12 2 1.7 6.3L20 10l-6.3 1.7L12 18l-1.7-6.3L4 10l6.3-1.7L12 2Z" />,
    check: <path d="m5 12 4.2 4L19 6" />,
    download: <><path d="M12 3v12" /><path d="m7 10 5 5 5-5" /><path d="M5 21h14" /></>,
    close: <><path d="m6 6 12 12M18 6 6 18" /></>,
  };
  return <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">{paths[name]}</svg>;
}

function App() {
  const inputRef = useRef();
  const [file, setFile] = useState(null);
  const [preview, setPreview] = useState(null);
  const [width, setWidth] = useState(1200);
  const [height, setHeight] = useState(800);
  const [format, setFormat] = useState('webp');
  const [quality, setQuality] = useState(85);
  const [status, setStatus] = useState('idle');
  const [message, setMessage] = useState('');
  const [downloadUrl, setDownloadUrl] = useState('');

  const selectFile = (selected) => {
    if (!selected) return;
    if (!supportedTypes.includes(selected.type) || selected.size > MAX_FILE_SIZE) {
      setMessage('Please choose a JPG, PNG, or WebP image under 8 MB.');
      return;
    }
    setFile(selected);
    setPreview(URL.createObjectURL(selected));
    setStatus('ready');
    setMessage('');
    setDownloadUrl('');
  };

  const processImage = async () => {
    if (!file) return;
    try {
      setStatus('uploading');
      setMessage('Preparing your secure upload…');
      const createResponse = await fetch('/api/uploads', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          filename: file.name,
          contentType: file.type,
          width: Number(width),
          height: Number(height),
          format,
          quality: Number(quality),
        }),
      });
      if (!createResponse.ok) throw new Error('Could not start this resize job.');
      const { jobId, uploadUrl } = await createResponse.json();

      setMessage('Uploading your image…');
      const uploadResponse = await fetch(uploadUrl, { method: 'PUT', headers: { 'Content-Type': file.type }, body: file });
      if (!uploadResponse.ok) throw new Error('Upload failed. Please try again.');

      setStatus('processing');
      setMessage('Resizing with PixelDrop…');
      const result = await waitForJob(jobId);
      setDownloadUrl(result.downloadUrl);
      setStatus('complete');
      setMessage('Your resized image is ready.');
    } catch (error) {
      setStatus('error');
      setMessage(error.message || 'Something went wrong. Please try again.');
    }
  };

  const waitForJob = async (jobId) => {
    for (let attempt = 0; attempt < 40; attempt += 1) {
      await new Promise((resolve) => setTimeout(resolve, 1500));
      const response = await fetch(`/api/jobs/${jobId}`);
      if (!response.ok) continue;
      const job = await response.json();
      if (job.status === 'complete') return job;
      if (job.status === 'failed') throw new Error(job.error || 'We could not resize this image.');
    }
    throw new Error('This is taking longer than expected. Please try again.');
  };

  const reset = () => {
    setFile(null); setPreview(null); setStatus('idle'); setMessage(''); setDownloadUrl('');
  };

  const busy = status === 'uploading' || status === 'processing';
  return <main>
    <nav>
      <a className="brand" href="/"><span className="brand-mark"><Icon name="spark" size={17} /></span>PixelDrop</a>
      <span className="nav-note">Fast, private image resizing</span>
    </nav>

    <section className="hero">
      <p className="eyebrow">IMAGE RESIZER</p>
      <h1>Make every pixel<br /><em>feel intentional.</em></h1>
      <p className="hero-copy">Resize and convert your images in seconds. No account, no clutter—just a polished result.</p>
    </section>

    <section className="workspace" aria-label="Image resize workspace">
      <div className={`dropzone ${file ? 'has-file' : ''}`} onClick={() => !file && inputRef.current.click()} onDragOver={(e) => e.preventDefault()} onDrop={(e) => { e.preventDefault(); selectFile(e.dataTransfer.files[0]); }}>
        <input ref={inputRef} type="file" accept="image/jpeg,image/png,image/webp" onChange={(e) => selectFile(e.target.files[0])} />
        {preview ? <div className="preview-wrap"><img src={preview} alt="Selected upload preview" /><button className="remove" onClick={(e) => { e.stopPropagation(); reset(); }} aria-label="Remove image"><Icon name="close" size={18} /></button><div className="file-pill"><Icon name="image" size={16} /><span>{file.name}</span><small>{(file.size / 1024 / 1024).toFixed(1)} MB</small></div></div>
          : <div className="drop-content"><span className="upload-orb"><Icon name="upload" size={26} /></span><h2>Drop your image here</h2><p>or <button onClick={(e) => { e.stopPropagation(); inputRef.current.click(); }}>browse from your device</button></p><small>JPG, PNG, or WebP · up to 8 MB</small></div>}
      </div>

      <div className="controls">
        <div className="control-heading"><span>Output settings</span><span className="dot" /></div>
        <div className="field-row">
          <label>Width <div className="input-unit"><input type="number" min="32" max="4000" value={width} onChange={(e) => setWidth(e.target.value)} disabled={busy} /><span>px</span></div></label>
          <label>Height <div className="input-unit"><input type="number" min="32" max="4000" value={height} onChange={(e) => setHeight(e.target.value)} disabled={busy} /><span>px</span></div></label>
        </div>
        <label>Format <div className="format-select">{['webp', 'jpeg', 'png'].map((type) => <button key={type} className={format === type ? 'selected' : ''} onClick={() => setFormat(type)} disabled={busy}>{type.toUpperCase()}</button>)}</div></label>
        <label>Quality <div className="range-row"><input type="range" min="50" max="100" value={quality} onChange={(e) => setQuality(e.target.value)} disabled={busy} /><output>{quality}%</output></div></label>
        {message && <p className={`status ${status}`}><span>{status === 'complete' ? <Icon name="check" size={16} /> : <span className="status-dot" />}</span>{message}</p>}
        {status === 'complete' ? <a className="action complete" href={downloadUrl} download><Icon name="download" size={19} />Download resized image</a>
          : <button className="action" onClick={processImage} disabled={!file || busy}>{busy ? <><span className="spinner" />{status === 'uploading' ? 'Uploading…' : 'Resizing…'}</> : <><Icon name="spark" size={18} />Resize image</>}</button>}
      </div>
    </section>
    <footer><span><Icon name="check" size={15} /> Files are automatically deleted after 24 hours</span><span>Built for the details that matter.</span></footer>
  </main>;
}

createRoot(document.getElementById('root')).render(<App />);
