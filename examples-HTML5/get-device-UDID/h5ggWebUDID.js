// LEGACY-JAVASCRIPTCORE-ONLY: This plugin returns a native Objective-C object
// synchronously and is not compatible with the WKWebView Promise/RPC bridge.
//put h5ggWebUdid.dylib into .app folder
var WebUDID = h5gg.loadPlugin("WebUDID", "h5ggWebUdid.dylib");

if(!WebUDID) throw "load dylib plugin failed!";

setTimeout(function(){ 

    //use h5ggWebUdid.mobileconfig, so put it into .app folder
    WebUDID.webudid("h5ggWebUdid", function(udid) 
    {
        setTimeout(function(){ alert(udid); }, 100);
    });
    
}, 500);

