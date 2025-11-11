// ============================================================================
// Macro: Channel Background Division & Recombine (Documented)
// Purpose:
//   1) Split the active multichannel image into separate channel images.
//   2) Duplicate one selected channel (default: channel 1; user-settable).
//   3) Apply Gaussian Blur (default sigma = 50 px; user-settable) to the copy.
//   4) Use Image Calculator to divide the ORIGINAL channel by the blurred copy,
//      creating a 32-bit result (division-based background correction).
//   5) Apply auto contrast with user-settable saturation (default 0.35%).
//   6) Convert the result to the requested bit-depth: 16-bit (default) or 8-bit.
//   7) Merge the processed channel back together with the other split channels.
//
// Notes & Assumptions:
//   - The active image is a multichannel stack or hyperstack.
//   - "Split Channels" names outputs as: "C<index>-<original title>".
//   - Merge supports up to 7 channels (ImageJ limitation). This macro enforces it.
//   - Intermediates can optionally be auto-closed after merging.
//
// Author: Jens Eriksson
// ============================================================================


// -----------------------------
// Section 0 — Small helpers
// -----------------------------

function isOpen(title) {
    list = getList("image.titles");
    for (ii = 0; ii < list.length; ii++) if (list[ii] == title) return true;
    return false;
}

function tryClose(title) {
    if (isOpen(title)) { selectWindow(title); close(); }
}

function expectedSplitTitles(origTitle, nC) {
    arr = newArray(nC);
    for (k = 1; k <= nC; k++) arr[k-1] = "C" + k + "-" + origTitle;
    return arr;
}

function clampChannelIndex(idx, nC) {
    idx = floor(idx);
    if (idx < 1) idx = 1;
    if (idx > nC) idx = nC;
    return idx;
}


// -----------------------------
// Section 1 — Inspect active image
// -----------------------------

origTitle = getTitle();
selectWindow(origTitle);

// Get dimensions: width, height, channels, slices (Z), frames (T)
getDimensions(w, h, nChannels, numSlices, numFrames);

if (nChannels < 2) {
    showMessage("Error", "This macro requires a multichannel image (>= 2 channels).");
    exit();
}
if (nChannels > 7) {
    showMessage("Error", "Merge Channels supports up to 7 channels. Active image has " + nChannels + ".");
    exit();
}


// -----------------------------
// Section 2 — Collect user parameters
// -----------------------------

Dialog.create("Channel Division Parameters");
Dialog.addNumber("Channel to process (1.." + nChannels + ")", 1);             // default: channel 1
Dialog.addNumber("Gaussian Blur sigma (pixels)", 50);                          // default: 50 px
Dialog.addNumber("Auto-contrast saturation (%)", 0.35);                        // default: 0.35%
Dialog.addChoice("Output bit-depth", newArray("16-bit","8-bit"), "16-bit");    // default: 16-bit
Dialog.addCheckbox("Keep intermediate images (split/blur/result)", false);
Dialog.show();

procChan   = clampChannelIndex(Dialog.getNumber(), nChannels);
blurSigma  = Dialog.getNumber();
satPercent = Dialog.getNumber();
bitChoice  = Dialog.getChoice();
keepInterm = Dialog.getCheckbox();


// -----------------------------
// Section 3 — Split channels
// -----------------------------
// Produces single-channel images named "C#-<origTitle>".

run("Split Channels");

// Record expected split titles and verify they exist
splitTitles = expectedSplitTitles(origTitle, nChannels);
for (c = 0; c < nChannels; c++) {
    if (!isOpen(splitTitles[c])) {
        showMessage("Error",
            "Expected split channel not found:\n  " + splitTitles[c] +
            "\nCheck that split naming is 'C#-OriginalTitle'.");
        // Attempt cleanup
        for (c2 = 0; c2 < nChannels; c2++) tryClose(splitTitles[c2]);
        exit();
    }
}


// -----------------------------
// Section 4 — Duplicate & blur the selected channel
// -----------------------------

procSrcTitle = splitTitles[procChan - 1];          // title of channel to process
selectWindow(procSrcTitle);

// Duplicate the selected channel for blurring
blurCopyTitle = "BlurCopy_of_" + procSrcTitle;
run("Duplicate...", "title=" + blurCopyTitle + " duplicate");

// Apply Gaussian Blur to the duplicate
// Note: Gaussian Blur on a stack applies to all slices automatically
selectWindow(blurCopyTitle);
run("Gaussian Blur...", "sigma=" + blurSigma + " stack");


// -----------------------------
// Section 5 — Divide original by blurred copy (32-bit)
// -----------------------------
// This performs division-based background correction.

selectWindow(procSrcTitle);
calcResultTitle = "Divided_" + procSrcTitle;


// Perform division - Image Calculator preserves stack structure
selectWindow(procSrcTitle);
imageCalculator("Divide create 32-bit stack", procSrcTitle, blurCopyTitle);
// Image Calculator creates a new window - get its title and rename
newCalcTitle = getTitle();
if (newCalcTitle != calcResultTitle) {
    selectWindow(newCalcTitle);
    rename(calcResultTitle);
}
// Verify the window exists and select it
if (!isOpen(calcResultTitle)) {
    showMessage("Error", "Failed to create or rename Image Calculator result window.");
    exit();
}


// -----------------------------
// Section 6 — Auto contrast on the result
// -----------------------------
// Apply enhance contrast on the 32-bit image before bit-depth reduction.

selectWindow(calcResultTitle);
run("Enhance Contrast...", "saturated=" + satPercent);


// -----------------------------
// Section 7 — Convert to requested bit-depth
// -----------------------------

selectWindow(calcResultTitle);
if (bitChoice == "16-bit") run("16-bit");
else                       run("8-bit");



// -----------------------------
// Section 8 — Recombine channels
// -----------------------------
// Replace processed channel and merge back to a multichannel image.


mergeSpec = "";
for (c = 1; c <= nChannels; c++) {
    chanKey = "c" + c + "=";
    if (c == procChan) mergeSpec = mergeSpec + chanKey + calcResultTitle + " ";
    else               mergeSpec = mergeSpec + chanKey + splitTitles[c-1] + " ";
}
mergeSpec = mergeSpec + "create";
run("Merge Channels...", mergeSpec);

// Get the merged result title and make it composite
mergedTitle = getTitle();
selectWindow(mergedTitle);
run("Make Composite");
recombinedTitle = "Recombined_" + origTitle;
selectWindow(mergedTitle);
rename(recombinedTitle);


// -----------------------------
// Section 9 — Cleanup (optional)
// -----------------------------

if (!keepInterm) {
    for (c = 0; c < nChannels; c++) tryClose(splitTitles[c]); // close split channels
    tryClose(blurCopyTitle);
    tryClose(calcResultTitle); // processed channel (now merged, use finalProcTitle)
}

// Bring final image to front
selectWindow(recombinedTitle);

// =============================
// End of macro
// =============================
