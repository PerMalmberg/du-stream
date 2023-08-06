# du-stream

A stream library for Dual Universe

Features provided by [DU-LuaC](https://github.com/wolfe-labs/DU-LuaC) are required so use it to build your project.

To run the example projects:
Build the project and paste the out/Controller.json and out/Worker.json onto the their respective programming board and link in this order:

Controller side:
1. Core
2. Emitter
3. Receiver

Worker:
1. Core
2. Emitter
3. Receiver
4. Screen

> Note: The stream will signal an error if the data to send is larger than can fit in 999 blocks since the header has a fixed size.