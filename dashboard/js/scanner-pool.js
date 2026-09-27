/*
 * A small pool of scanner workers. Falls back to scanning on the page itself
 * when workers are unavailable (for example when index.html is opened
 * directly from disk, where browsers block file:// workers).
 */
(function () {
  'use strict';

  const size = Math.max(1, Math.min(4, (navigator.hardwareConcurrency || 2) - 1));
  let workers = null;
  let nextId = 1;
  const pending = new Map();
  const idle = [];
  const queue = [];

  function startWorkers() {
    if (workers !== null) return workers;
    workers = [];
    try {
      for (let i = 0; i < size; i++) {
        const worker = new Worker('js/scanner-worker.js');
        worker.onmessage = (event) => {
          const { id, result, error } = event.data;
          const job = pending.get(id);
          pending.delete(id);
          idle.push(worker);
          pump();
          if (!job) return;
          if (error) job.reject(new Error(error));
          else job.resolve(result);
        };
        worker.onerror = (event) => {
          event.preventDefault();
          // A worker that cannot even load: give up on workers entirely.
          workers = [];
          idle.length = 0;
          for (const [id, job] of pending) {
            pending.delete(id);
            runInline(job);
          }
          while (queue.length) runInline(queue.shift());
        };
        workers.push(worker);
        idle.push(worker);
      }
    } catch (e) {
      workers = [];
      idle.length = 0;
    }
    return workers;
  }

  function runInline(job) {
    window.DiwanScanner.scanBlob(job.blob, job.options).then(job.resolve, job.reject);
  }

  function pump() {
    while (idle.length && queue.length) {
      const worker = idle.pop();
      const job = queue.shift();
      pending.set(job.id, job);
      worker.postMessage({ id: job.id, blob: job.blob, options: job.options });
    }
  }

  /** Scans an image Blob; resolves to { blob, extension, autoDetected, width, height }. */
  function scan(blob, options) {
    return new Promise((resolve, reject) => {
      const job = { id: nextId++, blob, options, resolve, reject };
      if (startWorkers().length === 0) {
        runInline(job);
        return;
      }
      queue.push(job);
      pump();
    });
  }

  window.ScannerPool = { scan, size };
})();
