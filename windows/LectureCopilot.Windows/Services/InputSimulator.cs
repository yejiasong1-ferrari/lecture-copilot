namespace LectureCopilot.Windows.Services;

public static class InputSimulator
{
    private const uint MouseLeftDown = 0x0002;
    private const uint MouseLeftUp = 0x0004;
    private const uint MouseWheel = 0x0800;

    public static void ScrollDown(int x, int y, int notches)
    {
        NativeMethods.SetCursorPos(x, y);
        NativeMethods.mouse_event(MouseWheel, 0, 0, unchecked((uint)(-120 * notches)), UIntPtr.Zero);
    }

    public static bool Chord(int modifier, int key)
    {
        if (!KeyDown(modifier)) return false;
        var pressed = Press(key);
        var released = KeyUp(modifier);
        return pressed && released;
    }

    public static bool Press(int key)
    {
        if (!KeyDown(key)) return false;
        return KeyUp(key);
    }

    public static void Click(int x, int y)
    {
        NativeMethods.SetCursorPos(x, y);
        Thread.Sleep(55);
        NativeMethods.mouse_event(MouseLeftDown, 0, 0, 0, UIntPtr.Zero);
        NativeMethods.mouse_event(MouseLeftUp, 0, 0, 0, UIntPtr.Zero);
    }

    public static void TypeText(string text)
    {
        var inputs = new List<NativeMethods.Input>(text.Length * 2);
        foreach (var character in text)
        {
            inputs.Add(Unicode(character, false));
            inputs.Add(Unicode(character, true));
        }
        if (inputs.Count > 0)
        {
            var sent = NativeMethods.SendInput((uint)inputs.Count, inputs.ToArray(), System.Runtime.InteropServices.Marshal.SizeOf<NativeMethods.Input>());
            if (sent != inputs.Count)
                Logger.Write($"Unicode input failed sent={sent}/{inputs.Count} error={System.Runtime.InteropServices.Marshal.GetLastWin32Error()}");
        }
    }

    private static bool KeyDown(int key) => SendVirtualKey(key, false);
    private static bool KeyUp(int key) => SendVirtualKey(key, true);

    private static bool SendVirtualKey(int key, bool up)
    {
        var input = new NativeMethods.Input
        {
            Type = NativeMethods.InputKeyboard,
            Union = new NativeMethods.InputUnion
            {
                Keyboard = new NativeMethods.KeyboardInput { Vk = (ushort)key, Flags = up ? NativeMethods.KeyEventFKeyUp : 0 }
            }
        };
        if (NativeMethods.SendInput(1, [input], System.Runtime.InteropServices.Marshal.SizeOf<NativeMethods.Input>()) == 1)
            return true;
        Logger.Write($"Keyboard input failed key=0x{key:X} up={up} error={System.Runtime.InteropServices.Marshal.GetLastWin32Error()}");
        return false;
    }

    private static NativeMethods.Input Unicode(char character, bool up) => new()
    {
        Type = NativeMethods.InputKeyboard,
        Union = new NativeMethods.InputUnion
        {
            Keyboard = new NativeMethods.KeyboardInput
            {
                Scan = character,
                Flags = NativeMethods.KeyEventFUnicode | (up ? NativeMethods.KeyEventFKeyUp : 0)
            }
        }
    };
}
