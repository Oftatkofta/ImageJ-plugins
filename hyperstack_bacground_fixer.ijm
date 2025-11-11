// =============================================================================
// Macro: Hyperstack Background Fixer
// In plain words, this script:
//   1) Splits the current multichannel image into one image per channel.
//   2) Makes a soft (blurred) version of the channel you want to clean up.
//   3) Divides the original channel by the blurred copy to remove background.
//   4) Boosts the contrast so the result is easier to see.
//   5) Converts every channel to the bit depth you choose (16-bit or 8-bit).
//   6) Puts all channels back together again.
//
// Things to know before you run it:
//   - Your starting image must have at least two channels.
//   - ImageJ only lets us merge up to 7 channels, so that is the upper limit.
//   - Intermediate images can be closed automatically when we are done.
//
// Author: Jens Eriksson
// =============================================================================


// ---------------------------------------------------------------------------
// Step 0 — Helper functions
// Simple utility pieces used throughout the script.
// ---------------------------------------------------------------------------

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


// ---------------------------------------------------------------------------
// Step 1 — Look at the image on screen
// We grab its title and basic dimensions so later steps know what to expect.
// ---------------------------------------------------------------------------

origTitle = getTitle();
selectWindow(origTitle);

// Save width, height, number of channels, slices (Z), and time frames (T)
getDimensions(w, h, nChannels, numSlices, numFrames);

if (nChannels < 2) {
    showMessage("Error", "This macro requires a multichannel image (>= 2 channels).");
    exit();
}
if (nChannels > 7) {
    showMessage("Error", "Merge Channels supports up to 7 channels. Active image has " + nChannels + ".");
    exit();
}


// ---------------------------------------------------------------------------
// Step 2 — Ask the user for settings
// A dialog lets the user pick which channel to fix and how strong the blur should be.
// ---------------------------------------------------------------------------

Dialog.create("Channel Division Parameters");
Dialog.addNumber("Channel to process (1.." + nChannels + ")", 1);             // default choice is channel 1
Dialog.addNumber("Gaussian Blur sigma (pixels)", 50);                          // default blur strength is 50 px
Dialog.addNumber("Auto-contrast saturation (%)", 0.35);                        // default contrast stretch is 0.35%
Dialog.addChoice("Output bit-depth", newArray("16-bit","8-bit"), "16-bit");    // default output is 16-bit
Dialog.addCheckbox("Keep intermediate images (split/blur/result)", false);
Dialog.show();

procChan   = clampChannelIndex(Dialog.getNumber(), nChannels);
blurSigma  = Dialog.getNumber();
satPercent = Dialog.getNumber();
bitChoice  = Dialog.getChoice();
keepInterm = Dialog.getCheckbox();


// ---------------------------------------------------------------------------
// Step 3 — Split the channels into separate images
// ImageJ names them "C<#>-<original title>".
// ---------------------------------------------------------------------------

run("Split Channels");

// Make sure every expected split image actually opened
splitTitles = expectedSplitTitles(origTitle, nChannels);
for (c = 0; c < nChannels; c++) {
    if (!isOpen(splitTitles[c])) {
        showMessage("Error",
            "Expected split channel not found:\n  " + splitTitles[c] +
            "\nCheck that split naming is 'C#-OriginalTitle'.");
        // Clean up anything we already opened, then stop the macro
        for (c2 = 0; c2 < nChannels; c2++) tryClose(splitTitles[c2]);
        exit();
    }
}


// ---------------------------------------------------------------------------
// Step 4 — Copy the channel we will correct and blur the copy
// The blur gives us the smooth background we want to divide out.
// ---------------------------------------------------------------------------

procSrcTitle = splitTitles[procChan - 1];          // title of channel to process
selectWindow(procSrcTitle);

// Duplicate the channel we want to correct
blurCopyTitle = "BlurCopy_of_" + procSrcTitle;
run("Duplicate...", "title=" + blurCopyTitle + " duplicate");

// Blur the duplicate. ImageJ applies the blur to the whole stack automatically.
selectWindow(blurCopyTitle);
run("Gaussian Blur...", "sigma=" + blurSigma + " stack");


// ---------------------------------------------------------------------------
// Step 5 — Divide the original channel by the blurred copy
// This is the background correction step.
// ---------------------------------------------------------------------------

selectWindow(procSrcTitle);
calcResultTitle = "Divided_" + procSrcTitle;


// Run the Image Calculator. "stack" keeps the full data cube intact.
selectWindow(procSrcTitle);
imageCalculator("Divide create 32-bit stack", procSrcTitle, blurCopyTitle);
// Image Calculator opens a new window. Rename it to the expected title.
newCalcTitle = getTitle();
if (newCalcTitle != calcResultTitle) {
    selectWindow(newCalcTitle);
    rename(calcResultTitle);
}
// Make sure the window exists. If not, explain the problem and stop.
if (!isOpen(calcResultTitle)) {
    showMessage("Error", "Failed to create or rename Image Calculator result window.");
    exit();
}


// ---------------------------------------------------------------------------
// Step 6 — Boost the contrast so details stand out
// We do this while the data is still in 32-bit precision.
// ---------------------------------------------------------------------------

selectWindow(calcResultTitle);
run("Enhance Contrast...", "saturated=" + satPercent);


// ---------------------------------------------------------------------------
// Step 7 — Convert to the bit depth the user selected
// All channels must match so ImageJ can merge them later.
// ---------------------------------------------------------------------------

selectWindow(calcResultTitle);
if (bitChoice == "16-bit") run("16-bit");
else                       run("8-bit");

// Convert every other channel so they all match the new bit depth
for (c = 0; c < nChannels; c++) {
    if (c == procChan - 1) continue;
    selectWindow(splitTitles[c]);
    if (bitChoice == "16-bit") run("16-bit");
    else                       run("8-bit");
}



// ---------------------------------------------------------------------------
// Step 8 — Put the channels back together
// We replace the cleaned channel and rebuild the multichannel image.
// ---------------------------------------------------------------------------


mergeSpec = "";
for (c = 1; c <= nChannels; c++) {
    chanKey = "c" + c + "=";
    if (c == procChan) mergeSpec = mergeSpec + chanKey + calcResultTitle + " ";
    else               mergeSpec = mergeSpec + chanKey + splitTitles[c-1] + " ";
}
mergeSpec = mergeSpec + "create";
run("Merge Channels...", mergeSpec);

// Rename the merged result and show it as a composite stack
mergedTitle = getTitle();
selectWindow(mergedTitle);
run("Make Composite");
recombinedTitle = "Recombined_" + origTitle;
selectWindow(mergedTitle);
rename(recombinedTitle);


// ---------------------------------------------------------------------------
// Step 9 — Optional cleanup
// Close the split channels and helper images if the user did not ask to keep them.
// ---------------------------------------------------------------------------

if (!keepInterm) {
    for (c = 0; c < nChannels; c++) tryClose(splitTitles[c]); // close each split channel
    tryClose(blurCopyTitle);
    tryClose(calcResultTitle); // close the processed channel window
}

// Bring the finished image to the front so the user sees it
selectWindow(recombinedTitle);

// =============================
// End of macro
// =============================
