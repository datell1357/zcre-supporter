namespace ZcreSupporter;

internal static class PetMenuIcon
{
    internal static Image Create(string target)
    {
        // Match the macOS menu's symbol meanings without depending on SF Symbols or a glyph font.
        var path = target switch
        {
            "image" => "M2.5,4.5 H17.5 V16.5 H2.5 Z M3,14 L7,9.5 11,13 13,11 17,15 M13,7 A1,1 0 1 1 11,7 A1,1 0 1 1 13,7",
            "/studio/image" => "M2.5,4.5 H11 M17.5,10 V16.5 H2.5 V4.5 M3,14 L7,9.5 11,13 13,11 17,15 M15,2 V8 M12,5 H18",
            "video" => "M2.5,5 H12.5 V15 H2.5 Z M12.5,8 L17.5,5.5 V14.5 L12.5,12",
            "/studio/video" => "M2.5,5 H11 M12.5,10 V15 H2.5 V5 M12.5,11 L17.5,9 V14.5 L12.5,12 M15,2 V7 M12.5,4.5 H17.5",
            "/studio/character-sheet" => "M6,2 H18 V14 M2,6 H14 V18 H2 Z M9.5,10 A1.5,1.5 0 1 1 6.5,10 A1.5,1.5 0 1 1 9.5,10 M4.5,16 C4.5,12 11.5,12 11.5,16",
            "/studio/partial-edit" => "M7,12 L14.5,3 C16,1.5 18.5,4 17,5.5 L9,13.5 Z M7,12 C3,11 5,16 2.5,17 C7,18 10,16 9,13.5",
            "/studio/image?tool=background-removal" => "M3,11 L11,3 17,9 9,17 H7 Z M8,6 L14,12 M9,17 H18",
            "/studio/image?tool=upscale" or "/studio/image?tool=upscale&media=video" => "M9,3 L10.8,8.2 16,10 10.8,11.8 9,17 7.2,11.8 2,10 7.2,8.2 Z M16,2 V6 M14,4 H18",
            "/studio/image?tool=resize" => "M3,8 V3 H8 M3,3 L8,8 M17,12 V17 H12 M17,17 L12,12",
            "/studio/frame-interpolation" => "M6,2 H18 V14 M2,6 H14 V18 H2 Z M5,6 V18 M11,6 V18 M2,10 H5 M2,14 H5 M11,10 H14 M11,14 H14",
            "/studio/video-translate" => "M2.5,3.5 H17.5 V14 H10 L6,17 V14 H2.5 Z M5,7 H8 M11,7 H15 M5,10.5 H10 M12,10.5 H15",
            "/studio/jiujitsu" => "M12.5,4 A1.5,1.5 0 1 1 9.5,4 A1.5,1.5 0 1 1 12.5,4 M10,7 L8,11 12,14 15,18 M8,11 L5,17 M9,8 L14,9 17,6 M9,8 L5,6 2,8",
            "/studio/audio" => "M2.5,8 V12 M6,4 V16 M10,2 V18 M14,5 V15 M17.5,8 V12",
            "/studio/canvas" => "M8,3 H3 V17 H17 V12 M8,12 L9,8 15,2 18,5 12,11 Z M13,4 L16,7",
            "home" => "M17,10 H3 M8,5 L3,10 8,15",
            "close" => "M5,5 L15,15 M15,5 L5,15",
            _ => throw new ArgumentException("Unknown radial menu icon target.", nameof(target))
        };
        var drawing = new DrawingGroup();
        drawing.Children.Add(new GeometryDrawing(Brushes.Transparent, null, new RectangleGeometry(new Rect(0, 0, 20, 20))));
        var pen = new Pen(Brushes.White, 1.5) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round, LineJoin = PenLineJoin.Round };
        drawing.Children.Add(new GeometryDrawing(null, pen, Geometry.Parse(path))); drawing.Freeze();
        var icon = new Image { Source = new DrawingImage(drawing), Width = 16, Height = 16, IsHitTestVisible = false, Focusable = false };
        return icon;
    }
}
