h5gg.require(8.0); //设定最低需求的H5GG版本号

//将插件dylib放到.app目录中调用//copy plugin dylib to .app folder
async function runPluginDemo() {
    var loaded = await h5gg.loadPlugin("MyAlert", "customAlert.dylib");

    if(!loaded || !loaded.loaded)
        throw "插件加载失败! Plugin Load Failed: " + (loaded && loaded.error);

    // WKWebView插件使用JSON RPC，不再向JavaScript暴露原生OC对象。
    var response = await h5gg.callPlugin(
        loaded.id,
        "alert2",
        ["标题文本AlertTitle", "内容文本AlertText"]
    );
    if(!response.ok) throw response.error;
}

runPluginDemo().catch(function(error) {
    console.error(error);
});
