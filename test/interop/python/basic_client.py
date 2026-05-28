import argparse
import asyncio

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client


async def run(
    command: str,
    server_args: list[str],
    cwd: str | None,
    expect_inspector_primitives: bool,
) -> None:
    params = StdioServerParameters(command=command, args=server_args, cwd=cwd)
    async with stdio_client(params) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()
            tools = await session.list_tools()
            names = {tool.name for tool in tools.tools}
            if "echo" not in names:
                raise RuntimeError(f"Expected echo tool, got {sorted(names)}")

            result = await session.call_tool(
                "echo",
                {"message": "from python client"},
            )
            content = result.content[0]
            text = getattr(content, "text", None)
            if text != "from python client":
                raise RuntimeError(f"Unexpected echo result: {result!r}")

            if expect_inspector_primitives:
                resources = await session.list_resources()
                uris = {str(resource.uri) for resource in resources.resources}
                if "inspector://status" not in uris:
                    raise RuntimeError(f"Expected inspector resource, got {sorted(uris)}")

                prompts = await session.list_prompts()
                names = {prompt.name for prompt in prompts.prompts}
                if "inspector-summary" not in names:
                    raise RuntimeError(f"Expected inspector prompt, got {sorted(names)}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--server-command", required=True)
    parser.add_argument("--server-args", default="")
    parser.add_argument("--server-cwd")
    parser.add_argument("--expect-inspector-primitives", action="store_true")
    args = parser.parse_args()
    server_args = [part for part in args.server_args.split(" ") if part]
    asyncio.run(
        run(
            args.server_command,
            server_args,
            args.server_cwd,
            args.expect_inspector_primitives,
        )
    )
    print("python client interop passed")


if __name__ == "__main__":
    main()
