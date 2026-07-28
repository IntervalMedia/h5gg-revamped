// H5GG-Revamped v8.0+ only. Requires await for all h5gg calls.
// These helpers are async because h5gg.getValue is a Promise.

async function readUTF16String(address, maxlen)
{
    var str = "";
    for (var s = 0; !maxlen||s<maxlen; s++) {
        var charCode = Number(await h5gg.getValue(address + s * 2, "U16"));
        if(!charCode) break;
        str += String.fromCharCode(charCode);
    }
    return str;
}

async function readUTF32String(address, maxlen)
{
    var str = "";
    for (var s = 0; !maxlen||s<maxlen; s++) {
        var charCode = Number(await h5gg.getValue(address + s * 4, "U32"));
        if(!charCode) break;
        str += String.fromCharCode(charCode);
    }
    return str;
}


//This is usually slower, It is recommended to cache it

//var str1 = await readUTF16String(addr);
//var str2 = await readUTF16String(addr, 20);
//var str3 = await readUTF32String(addr);
//var str4 = await readUTF32String(addr, 20);
