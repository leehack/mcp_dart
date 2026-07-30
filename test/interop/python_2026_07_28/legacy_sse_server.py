import argparse
import asyncio

import uvicorn
from mcp.server import MCPServer

mcp = MCPServer("python-2.0.0-legacy-sse-server", version="1.0.0")


@mcp.tool()
def calculate(operation: str, a: float, b: float) -> str:
    """Perform one basic arithmetic operation."""
    if operation == "add":
        value = a + b
    elif operation == "subtract":
        value = a - b
    elif operation == "multiply":
        value = a * b
    elif operation == "divide":
        value = a / b
    else:
        raise ValueError(f"Unknown operation: {operation}")
    if value.is_integer():
        value = int(value)
    return f"Result: {value}"


async def run(host: str, port: int) -> None:
    config = uvicorn.Config(
        mcp.sse_app(host=host),
        host=host,
        port=port,
        log_level="warning",
    )
    server = uvicorn.Server(config)
    server_task = asyncio.create_task(server.serve())
    while not server.started and not server_task.done():
        await asyncio.sleep(0.01)
    if server_task.done():
        await server_task
        raise RuntimeError("Python legacy SSE server stopped before becoming ready")
    print(
        f"Python legacy SSE interop server listening on "
        f"http://{host}:{port}/sse",
        flush=True,
    )
    await server_task


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, required=True)
    args = parser.parse_args()
    asyncio.run(run(args.host, args.port))


if __name__ == "__main__":
    main()
