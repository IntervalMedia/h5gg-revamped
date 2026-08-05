
//Test function to demonstrate how to use the h5gg API to search for a number and copy the first result to the clipboard.
async function findAndCopyFirstMatch() {

    await h5gg.clearResults();
    await h5gg.searchNumber(
        "42",
        "I32",
        "0x100000000",
        "0x200000000"
    );

    const count = await h5gg.getResultsCount();
    if (count === 0) return;

    await h5gg.alert(`Searched for "42". Found ${count} results. Copying the first one to clipboard...`);

    const [result] = await h5gg.getResults(1, 0);
    if (result) {
        await h5gg.copyText(`${result.address} = ${result.value} [${result.type}]`);
    }
}