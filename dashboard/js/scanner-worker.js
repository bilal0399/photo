/* Runs scans off the main thread so the dashboard stays responsive. */
importScripts('scanner-core.js');

self.onmessage = async (event) => {
  const { id, blob, options } = event.data;
  try {
    const result = await self.DiwanScanner.scanBlob(blob, options);
    self.postMessage({ id, result });
  } catch (error) {
    self.postMessage({ id, error: String((error && error.message) || error) });
  }
};
