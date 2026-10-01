fn main() {
    #[cfg(windows)]
    {
        let mut resource = winresource::WindowsResource::new();
        resource
            .set_icon("resources/icon.ico")
            .set("ProductName", "Gosh Calc")
            .set("FileDescription", "Gosh Calc desktop calculator")
            .set("LegalCopyright", "Copyright © 2026 goshitsarch-eng");
        if let Err(error) = resource.compile() {
            panic!("Cannot compile Windows application resources: {error}");
        }
    }
}
