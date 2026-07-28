// H5GG-Revamped v8.0+ only. Requires await for all h5gg calls.
(async () => {

await h5gg.require(8.0);

var modules = await h5gg.getRangesList("UnityFramework"); //module file name

var base = modules[0].start; //module base addr in runtime memory

var addr = Number(base) + 0x01915304; //offset

await patchBytes(addr,  "00E0AFD2C0035FD6"); //bytes

/********************************************************/
//only jailbroken devices can do this
async function patchBytes(addr, hex) {
    for(i = 0;i<hex.length/2;i++) {
        var item = parseInt(hex.substring(i*2, i*2+2), 16);
        await h5gg.setValue(addr+i,item, "U8");
    }
}
/********************************************************/

})();
