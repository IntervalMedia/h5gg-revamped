# H5GG

H5GG provides an iOS-hosted frontend contract for inspecting and modifying a selected process through an embedded web interface.

## Language

**Frontend contract**:
The complete JavaScript-visible surface provided by the H5GG host, including callable operations, host callbacks, and injected runtime values.
_Avoid_: JavaScript API when referring only to one part of the surface

**Bridge method**:
An allowlisted asynchronous operation exposed on `window.h5gg` and completed by the native host.
_Avoid_: Native method, JavaScriptCore method

**Window-control function**:
A global asynchronous operation that controls the floating H5GG window or button rather than the memory engine.
_Avoid_: Bridge method

**Host callback**:
An optional function defined by the frontend and invoked by the native host when a host event occurs.
_Avoid_: Event handler when the host calls a named global directly

**Injected runtime value**:
A host-owned JavaScript value that describes or supports the current embedded runtime.
_Avoid_: Configuration setting
