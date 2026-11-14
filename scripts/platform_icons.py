"""OS- en apparaat-iconen (zelfde stijl als bingr.online). Gebruikt door build_app_pages.py.
Dezelfde set staat als PLAT_ICONS in site/index.html; pas ze samen aan."""

ICONS = {
    "iPhone": ("0 0 48 48", "fill=\"none\" stroke=\"currentColor\" stroke-width=\"2.6\" stroke-linecap=\"round\" stroke-linejoin=\"round\"",
        "<rect x=\"14\" y=\"4\" width=\"20\" height=\"40\" rx=\"5\"/><path d=\"M21 8h6\"/>"),
    "iPad": ("0 0 48 48", "fill=\"none\" stroke=\"currentColor\" stroke-width=\"2.6\" stroke-linecap=\"round\" stroke-linejoin=\"round\"",
        "<rect x=\"9\" y=\"4\" width=\"30\" height=\"40\" rx=\"4\"/><path d=\"M21 39h6\"/>"),
    "Mac": ("0 0 48 48", "fill=\"none\" stroke=\"currentColor\" stroke-width=\"2.6\" stroke-linecap=\"round\" stroke-linejoin=\"round\"",
        "<rect x=\"8\" y=\"9\" width=\"32\" height=\"22\" rx=\"2.5\"/><path d=\"M3 37h42l-3-6H6z\"/>"),
    "Apple Watch": ("0 0 48 48", "fill=\"none\" stroke=\"currentColor\" stroke-width=\"2.6\" stroke-linecap=\"round\" stroke-linejoin=\"round\"",
        "<rect x=\"12\" y=\"12\" width=\"24\" height=\"24\" rx=\"7\"/><path d=\"M17 12l1.5-8h11l1.5 8M17 36l1.5 8h11l1.5-8\"/>"),
    "Apple TV": ("-2.2 -2.23 23.9 23.9", "fill=\"currentColor\" stroke=\"none\"",
        "<path d=\"M5.20687 19.4314L14.2907 19.4314C15.949 19.4314 17.3557 19.2815 18.3579 18.2793C19.3476 17.2792 19.4976 15.8974 19.4976 14.2246L19.4976 5.22355C19.4976 3.55067 19.3476 2.1668 18.3579 1.16882C17.3536 0.176964 15.949 0.0166814 14.2907 0.0166814L5.18577 0.0166814C3.55067 0.0166814 2.14188 0.179074 1.14179 1.17093C0.149932 2.17102 0 3.55489 0 5.1921L0 14.2246C0 15.8974 0.147822 17.2917 1.13968 18.2793C2.14188 19.2815 3.5361 19.4314 5.20687 19.4314ZM4.93695 17.8607C3.93656 17.8607 2.87758 17.7212 2.2877 17.1313C1.69781 16.5414 1.57069 15.497 1.57069 14.4945L1.57069 4.98508C1.57069 3.95535 1.69781 2.90461 2.28559 2.31473C2.87547 1.72274 3.94078 1.58737 4.9684 1.58737L14.5606 1.58737C15.561 1.58737 16.6179 1.72696 17.2078 2.31684C17.7997 2.90672 17.9269 3.95113 17.9269 4.95363L17.9269 14.4945C17.9269 15.497 17.7976 16.5414 17.2078 17.1313C16.6179 17.7233 15.561 17.8607 14.5606 17.8607Z\"/><path d=\"M4.85163 12.6004C5.26284 12.6004 5.4373 12.3138 5.94819 12.3138C6.47155 12.3138 6.59616 12.6004 7.04476 12.6004C7.49335 12.6004 7.79241 12.1768 8.09148 11.7655C8.39054 11.3045 8.54007 10.8434 8.54007 10.8185C8.52761 10.8185 7.64288 10.4571 7.64288 9.46027C7.64288 8.61293 8.32823 8.22664 8.36562 8.18925C7.92948 7.56621 7.23167 7.54128 7.04476 7.54128C6.53386 7.54128 6.12265 7.82789 5.86097 7.82789C5.58683 7.82789 5.22546 7.56621 4.77687 7.56621C3.95444 7.56621 3.1071 8.2391 3.1071 9.53503C3.1071 10.345 3.40616 11.1923 3.79245 11.7406C4.14136 12.2141 4.42796 12.6004 4.85163 12.6004ZM5.89835 7.45406C6.5214 7.45406 7.16937 6.78117 7.15691 6.04597C7.16937 6.00859 7.15691 5.95875 7.14444 5.92136C6.48402 5.94628 5.81112 6.60671 5.81112 7.32945C5.81112 7.36683 5.81112 7.42914 5.82359 7.4416C5.83605 7.45406 5.86097 7.45406 5.89835 7.45406ZM11.0073 12.5755C11.2192 12.5755 11.4435 12.563 11.5556 12.5381L11.5805 12.5257L11.5805 11.7157L11.5432 11.7157C11.4809 11.7282 11.3313 11.7406 11.2316 11.7406C10.8578 11.7406 10.6958 11.5662 10.6958 11.1799L10.6958 8.60046L11.593 8.60046L11.593 7.77804L10.6958 7.77804L10.6958 6.65656L9.68648 6.65656L9.68648 7.77804L9.00112 7.77804L9.00112 8.60046L9.68648 8.60046L9.68648 11.292C9.68648 12.2017 10.0728 12.5755 11.0073 12.5755ZM13.6864 12.5381L14.7332 12.5381L16.4029 7.77804L15.3562 7.77804L14.2223 11.4914L13.0759 7.77804L11.9917 7.77804Z\"/>"),
    "CarPlay": ("0 0 48 48", "fill=\"none\" stroke=\"currentColor\" stroke-width=\"2.6\" stroke-linecap=\"round\" stroke-linejoin=\"round\"",
        "<rect x=\"5\" y=\"9\" width=\"38\" height=\"30\" rx=\"6\"/><path d=\"M14 30l3-8.5h14l3 8.5M13 30h22\"/><circle cx=\"17.5\" cy=\"30\" r=\"1\" fill=\"currentColor\"/><circle cx=\"30.5\" cy=\"30\" r=\"1\" fill=\"currentColor\"/>"),
    "Windows": ("-1 -1 26 26", "fill=\"currentColor\" stroke=\"none\"",
        "<path d=\"M3.5 3.5h7.9v7.9H3.5zM12.6 3.5h7.9v7.9h-7.9zM3.5 12.6h7.9v7.9H3.5zM12.6 12.6h7.9v7.9h-7.9z\"/>"),
    "Android": ("0 0 48 48", "fill=\"none\" stroke=\"currentColor\" stroke-width=\"2.6\" stroke-linecap=\"round\" stroke-linejoin=\"round\"",
        "<rect x=\"14\" y=\"4\" width=\"20\" height=\"40\" rx=\"5\"/><circle cx=\"24\" cy=\"9\" r=\"1.3\" fill=\"currentColor\"/>"),
    "Android TV": ("0 0 48 48", "fill=\"none\" stroke=\"currentColor\" stroke-width=\"2.6\" stroke-linecap=\"round\" stroke-linejoin=\"round\"",
        "<rect x=\"4\" y=\"8\" width=\"40\" height=\"26\" rx=\"3\"/><path d=\"M17 41h14M24 34v7\"/>"),
    "Samsung TV": ("0 0 48 48", "fill=\"none\" stroke=\"currentColor\" stroke-width=\"2.6\" stroke-linecap=\"round\" stroke-linejoin=\"round\"",
        "<rect x=\"4\" y=\"8\" width=\"40\" height=\"26\" rx=\"3\"/><path d=\"M17 41h14M24 34v7\"/>"),
    "Web": ("0 0 48 48", "fill=\"none\" stroke=\"currentColor\" stroke-width=\"2.6\" stroke-linecap=\"round\" stroke-linejoin=\"round\"",
        "<circle cx=\"24\" cy=\"24\" r=\"19\"/><path d=\"M5 24h38M24 5c5.5 5.2 8 11.6 8 19s-2.5 13.8-8 19c-5.5-5.2-8-11.6-8-19s2.5-13.8 8-19z\"/>"),
    "Homey Pro": ("0 0 48 48", "fill=\"none\" stroke=\"currentColor\" stroke-width=\"2.6\" stroke-linecap=\"round\" stroke-linejoin=\"round\"",
        "<path d=\"M6 33a18 18 0 0 1 36 0z\"/><path d=\"M4 38h40\"/><circle cx=\"24\" cy=\"25\" r=\"2\" fill=\"currentColor\"/>"),
    "Homey Cloud": ("0 0 48 48", "fill=\"none\" stroke=\"currentColor\" stroke-width=\"2.6\" stroke-linecap=\"round\" stroke-linejoin=\"round\"",
        "<path d=\"M14 37h21a8.5 8.5 0 0 0 1.2-16.9A11.5 11.5 0 0 0 14.1 22 7.5 7.5 0 0 0 14 37z\"/>"),
    "Homey": ("0 0 48 48", "fill=\"none\" stroke=\"currentColor\" stroke-width=\"2.6\" stroke-linecap=\"round\" stroke-linejoin=\"round\"",
        "<path d=\"M6 33a18 18 0 0 1 36 0z\"/><path d=\"M4 38h40\"/><circle cx=\"24\" cy=\"25\" r=\"2\" fill=\"currentColor\"/>"),
    "Browser": ("0 0 48 48", "fill=\"none\" stroke=\"currentColor\" stroke-width=\"2.6\" stroke-linecap=\"round\" stroke-linejoin=\"round\"",
        "<circle cx=\"24\" cy=\"24\" r=\"19\"/><path d=\"M5 24h38M24 5c5.5 5.2 8 11.6 8 19s-2.5 13.8-8 19c-5.5-5.2-8-11.6-8-19s2.5-13.8 8-19z\"/>"),
}

ALIASES = {"local": "Homey Pro", "cloud": "Homey Cloud", "ios": "iPhone", "macos": "Mac", "watchos": "Apple Watch",
           "tvos": "Apple TV", "browser": "Web"}


def name(p):
    return ALIASES.get(str(p).lower(), p)


def svg(p):
    v = ICONS.get(name(p))
    if not v:
        return ""
    return f'<svg viewBox="{v[0]}" {v[1]} aria-hidden="true">{v[2]}</svg>'
