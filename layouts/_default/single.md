# {{ .Title }}
{{ with .Description }}
{{ . }}
{{ end }}
Canonical: {{ .Permalink }}
{{ if not .Date.IsZero }}Published: {{ .Date.Format "2006-01-02" }}{{ end }}

---

{{ .RawContent }}
