from pypdf import PdfReader

path = "/Users/immanuellaumoren/Desktop/GradPath/Immanuella Umoren's Official Transcript .pdf"
reader = PdfReader(path)
for i, page in enumerate(reader.pages):
    print(f"\n===PAGE {i+1}===")
    print(page.extract_text())
