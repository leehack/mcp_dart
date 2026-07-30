import argparse
import asyncio
import json

from mcp import ClientSession
from mcp.client.sse import sse_client


async def run(url: str) -> None:
    async with sse_client(url) as (read, write):
        async with ClientSession(read, write) as session:
            initialized = await session.initialize()
            if initialized.protocol_version != "2025-11-25":
                raise RuntimeError(
                    "Expected protocol 2025-11-25, got "
                    f"{initialized.protocol_version}"
                )
            if initialized.server_info.name != "example-dart-server":
                raise RuntimeError(
                    f"Unexpected Dart server identity: {initialized.server_info!r}"
                )

            tools = await session.list_tools()
            names = {tool.name for tool in tools.tools}
            if "calculate" not in names:
                raise RuntimeError(f"Expected calculate tool, got {sorted(names)}")

            result = await session.call_tool(
                "calculate",
                {"operation": "add", "a": 20, "b": 22},
            )
            text = getattr(result.content[0], "text", None)
            if text != "Result: 42":
                raise RuntimeError(f"Unexpected calculate result: {result!r}")

            print(
                json.dumps(
                    {
                        "protocolVersion": initialized.protocol_version,
                        "serverName": initialized.server_info.name,
                        "toolCount": len(tools.tools),
                        "result": text,
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
