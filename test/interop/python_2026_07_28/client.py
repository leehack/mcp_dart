import argparse
import asyncio
import json

from mcp.client import Client
from mcp_types import Implementation, TextContent


async def run(url: str) -> None:
    async with Client(
        url,
        mode="auto",
        client_info=Implementation(
            name="python-2026-07-28-interop-client",
            version="0.0.0",
        ),
    ) as client:
        if client.protocol_version != "2026-07-28":
            raise RuntimeError(
                f"Expected protocol 2026-07-28, got {client.protocol_version}"
            )

        tools = await client.list_tools()
        names = {tool.name for tool in tools.tools}
        if "echo" not in names:
            raise RuntimeError(f"Expected echo tool, got {sorted(names)}")

        message = "from Python 2026-07-28"
        result = await client.call_tool("echo", {"message": message})
        if not result.content or not isinstance(result.content[0], TextContent):
            raise RuntimeError(f"Expected text echo result, got {result!r}")
        if result.content[0].text != message:
            raise RuntimeError(f"Unexpected echo result: {result!r}")

        print(
            json.dumps(
                {
                    "protocolVersion": client.protocol_version,
                    "serverInfo": client.server_info.model_dump(
                        mode="json", by_alias=True
                    ),
                    "toolCount": len(tools.tools),
                    "echo": result.content[0].text,
                }
            ),
            flush=True,
        )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", required=True)
    args = parser.parse_args()
    asyncio.run(run(args.url))


if __name__ == "__main__":
    main()
