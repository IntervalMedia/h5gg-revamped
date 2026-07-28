// H5GG-Revamped v8.0+ only. Requires await for all h5gg calls.
(async () => {

await h5gg.require(8.0);

await h5gg.clearResults();
await h5gg.searchNumber("123", "I32", "0x0", "0xFFFFFFFF00000000");
var count = await h5gg.getResultsCount();
var results = await h5gg.getResults(count);

var locker = setInterval(async function() {
    console.log("running...");
    for(var i=0; i<count; i++) {
        await h5gg.setValue(results[i].address, "456", "I32");
    }
},
500  //lock/freeze time interval (millseconds)
);

//then we can cancel the lock/freeze:
//clearInterval(locker);

})();
