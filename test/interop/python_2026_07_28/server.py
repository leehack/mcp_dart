import argparse
import asyncio

import uvicorn
from mcp.server.mcpserver import MCPServer

mcp = MCPServer(
    "python-2026-07-28-interop-server",
    version="0.0.0",
)


@mcp.tool()
def python_echo(message: str) -> str:
    """Return the supplied message unchanged."""
    return message


async def run(host: str, port: int) -> None:
    config = uvicorn.Config(
        mcp.streamable_http_app(stateless_http=True, host=host),
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
        raise RuntimeError("Python MCP server stopped before becoming ready")
    print(
        f"Python 2026-07-28 interop server listening on "
        f"http://{host}:{port}/mcp",
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
