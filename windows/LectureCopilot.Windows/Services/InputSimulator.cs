namespace LectureCopilot.Windows.Services;

public static class InputSimulator
{
    private const uint MouseLeftDown = 0x0002;
    private const uint MouseLeftUp = 0x0004;

    public static void Chord(int modifier, int key)
    {
        KeyDown(modifier);
        Press(key);
        KeyUp(modifier);
    }

    public static void Press(int key)
    {
        KeyDown(key);
        KeyUp(key);
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
            NativeMethods.SendInput((uint)inputs.Count, inputs.ToArray(), System.Runtime.InteropServices.Marshal.SizeOf<NativeMethods.Input>());
    }

    private static void KeyDown(int key) => SendVirtualKey(key, false);
    private static void KeyUp(int key) => SendVirtualKey(key, true);

    private static void SendVirtualKey(int key, bool up)
    {
        var input = new NativeMethods.Input
        {
            Type = NativeMethods.InputKeyboard,
            Union = new NativeMethods.InputUnion
            {
                Keyboard = new NativeMethods.KeyboardInput { Vk = (ushort)key, Flags = up ? NativeMethods.KeyEventFKeyUp : 0 }
            }
        };
        NativeMethods.SendInput(1, [input], System.Runtime.InteropServices.Marshal.SizeOf<NativeMethods.Input>());
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
