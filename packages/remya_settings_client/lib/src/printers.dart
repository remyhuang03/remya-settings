/// CUPS printers: live state read with `Get printers`; each write takes JSON.
const printersFeature = 'printers';

/// `{"name": printer}`: the current user's default printer.
const defaultPrinterId = 'printers.default';

/// `{"name": printer}`: sends the CUPS test page.
const printTestPageId = 'printers.test-page';

/// `{"name": printer, "paused": bool}`: stops or resumes the printer.
const pausePrinterId = 'printers.pause';

/// `{"id": "<printer>-<number>"}`: cancels one queued job.
const cancelPrintJobId = 'printers.cancel-job';

/// `{"name": printer}`: deletes the CUPS queue.
const removePrinterId = 'printers.remove';
