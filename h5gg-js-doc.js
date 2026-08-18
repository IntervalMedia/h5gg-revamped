**************** H5GG JavaScript 引擎文档 (v8.0, WKWebView, 异步API) ********************

注意: 这是 H5GG-Revamped v8.0, 使用全新的 WKWebView 桥接。所有 h5gg 方法都返回 Promise, 必须用 await 调用。旧版 H5GG (< v8.0) 不兼容这些新API。

未来可能会加入同步/异步双兼容支持。

h5gg 是引擎对象, 可以调用以下函数 (类似安卓GG的 Lua 接口, 但参数略有不同)

await h5gg.require(版本号); //设置脚本所需的最小 H5GG 版本号, 写在脚本第一行

h5gg.setFloatTolerance('浮点误差'); //设置 F32/F64 浮点搜索的误差范围, 默认 0.0

await h5gg.searchNumber('数值', '类型', '搜索下限', '搜索上限'); //搜索或改善搜索精确数值

await h5gg.searchNearby('数值', '类型', '邻近范围'); //邻近搜索

await h5gg.getValue('地址', '类型'); //读取指定地址的值, 返回值字符串

await h5gg.setValue('地址', '数值', '类型'); //修改指定地址的值, 返回成功或失败

await h5gg.editAll('数值', '类型'); //修改全部搜索结果, 返回成功修改数量

await h5gg.getResultsCount(); //获取搜索结果总数

await h5gg.getResults('获取数量', '跳过数量'); //获取结果数组, 每个元素有 address, value, type 属性

await h5gg.clearResults(); //清除搜索结果, 重新开始搜索

await h5gg.getRangesList('模块文件名'); //返回模块数组, 模块有 start(基址), end(结束地址), name(路径) 属性
(模块文件名=0 返回APP主程序模块信息, 不传参返回全部模块列表)

const plugin = await h5gg.loadPlugin('Objective-C 类名', 'dylib 文件路径'); //WK插件实现H5GGPluginRPC并返回JSON句柄
const reply = await h5gg.callPlugin(plugin.id, '方法名', ['JSON参数']); //返回 {ok,result} 或 {ok:false,error}

await h5gg.searchHex('DE AD ?? E?', '0x0', '0x200000000'); //首次搜索，后续调用改善结果；?表示通配半字节
await h5gg.searchFilter('100', 'I32', 0); //筛选当前结果：0等于、2大于、3小于
await h5gg.readMemoryPage('0x1000', 256); //返回字节/null标记、可读数量和complete状态
await h5gg.dumpMemory('0x1000', '0x2000', 'dump.bin'); //异步流式导出；可查询getDumpStatus()或调用cancelDump()

仅跨进程版 APP 可用:

await h5gg.setTargetProc(进程号); //设置目标进程, 返回成功或失败

await h5gg.getProcList('进程名'); //获取进程数组, 元素有 pid(进程号), name(进程名) 属性
(不传参返回所有运行中的APP进程列表)

其他 API (异步调用, 通常不需要 await 返回值):

setButtonImage(图标); //设置悬浮按钮图标, 可传入 http 图片地址或 base64 编码 DataURL

setButtonAction(JS 回调函数); //自定义悬浮按钮点击动作

setWindowRect(x, y, width, height); //修改悬浮窗位置和尺寸

setWindowDrag(x, y, width, height); //设置 H5 页面中可拖拽悬浮窗的区域

setWindowTouch(是否穿透); //true=悬浮窗触控穿透, false=悬浮窗捕获触控

setWindowVisible(是否显示); //设置悬浮窗可见性

setLayoutAction(JS 回调函数); //屏幕旋转或 iPad 分屏尺寸变化时的回调, 参数 (width, height)

注意事项:

1: 地址参数支持 0x 开头十六进制或十进制自动识别, 其他参数必须为字符串格式

2: 浮点类型: F32, F64。有符号类型: I8, I16, I32, I64。无符号类型: U8, U16, U32, U64

3: 如果搜索结果较多, 不要一次性用 getResults 获取全部数据, 应分段获取避免内存不足

4: 搜索结果的地址和值均为字符串类型, 做数字运算请用 Number(x) 转换后再运算

5: 数值类型可用 x.toString(16) 转换为十六进制字符串, x 必须为数值类型

6: 搜索支持范围格式, 如 "50~100", "2.3~7.8", searchNumber 和 searchNearby 都支持

7: 所有 h5gg 调用现在都是异步的, 返回 Promise。脚本需要包装在 async 函数中使用 await。

8: 旧版使用同步 h5gg 调用的脚本需要更新才能在 v8.0 中使用。

9: 悬浮窗默认尺寸为 370x370, 可通过 JS API 设置位置和尺寸。
