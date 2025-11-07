#!/usr/bin/env python3

"""
Script to get the CGWindowID of Avira Security on macOS
Requires: pip3 install pyobjc-framework-Quartz
"""

try:
    from Quartz import CGWindowListCopyWindowInfo, kCGWindowListOptionAll, kCGNullWindowID
except ImportError:
    print("Error: PyObjC not installed")
    print("Install with: pip3 install pyobjc-framework-Quartz")
    exit(1)

def get_avira_windows():
    """Get all Avira windows with their CGWindowIDs"""
    windows = CGWindowListCopyWindowInfo(kCGWindowListOptionAll, kCGNullWindowID)
    avira_windows = []

    if windows is None:
        return avira_windows

    for window in windows:
        owner = window.get('kCGWindowOwnerName', '')

        # Check if it's an Avira window
        if 'Avira' in owner or 'AviraProtect' in owner:
            window_id = window.get('kCGWindowNumber')
            window_name = window.get('kCGWindowName', '(no name)')
            window_layer = window.get('kCGWindowLayer', 'N/A')
            bounds = window.get('kCGWindowBounds', {})

            avira_windows.append({
                'id': window_id,
                'name': window_name,
                'owner': owner,
                'layer': window_layer,
                'x': bounds.get('X', 0),
                'y': bounds.get('Y', 0),
                'width': bounds.get('Width', 0),
                'height': bounds.get('Height', 0)
            })

    return avira_windows

def main():
    windows = get_avira_windows()

    if not windows:
        print("-1")

    for i, win in enumerate(windows, 1):
        if win['x'] != 0 and win['y'] != 0:
            print(win['id'])

if __name__ == '__main__':
    main()

