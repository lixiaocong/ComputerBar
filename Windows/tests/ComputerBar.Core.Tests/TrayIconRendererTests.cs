using ComputerBar.Core;

namespace ComputerBar.Core.Tests;

public sealed class TrayIconRendererTests
{
    [Fact]
    public void RenderUsagePieCreatesStableNonEmptyIcon()
    {
        var renderer = new TrayIconRenderer();
        using var icon = renderer.Render([new TrayHostStatus("pc", 64)], 32).Icon;
        var result = renderer.Render([new TrayHostStatus("pc", 64)], 32);

        using (result.Icon)
        {
            Assert.Equal(32, result.Width);
            Assert.Equal(32, result.Height);
            Assert.True(result.HasNonTransparentPixels);
        }
    }

    [Fact]
    public void RenderErrorCreatesStableNonEmptyIcon()
    {
        var renderer = new TrayIconRenderer();
        var result = renderer.Render([new TrayHostStatus("dev", null, true, "ssh failed")], 32);

        using (result.Icon)
        {
            Assert.Equal(32, result.Width);
            Assert.Equal(32, result.Height);
            Assert.True(result.HasNonTransparentPixels);
        }
    }
}
