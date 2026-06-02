from mcp.server.fastmcp import FastMCP

mcp = FastMCP("python-interop-server")


@mcp.tool()
def echo(message: str) -> str:
    """Echo a message with a Python marker."""
    return f"python: {message}"


@mcp.tool()
def add(a: int, b: int) -> int:
    """Add two integers."""
    return a + b


if __name__ == "__main__":
    mcp.run()
