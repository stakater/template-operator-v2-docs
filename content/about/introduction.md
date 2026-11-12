# Introduction

Managing Kubernetes clusters at scale is complex. Platform teams have to keep dozens or hundreds of tenant namespaces consistent, secure, and up to date, while still letting application teams move fast and customize what they need. Doing this by hand quickly turns into copy-pasted YAML, drift between environments, and no clear answer to "who owns this resource and is it still needed?"

**Template Operator v2** is designed to address these challenges by giving platform teams a clean way to publish reusable templates, and giving application teams a simple way to consume them. Templates are authored once, parameterized for each consumer, and rendered into the right namespaces by the operator. With Template Operator v2, you can:

- **Define reusable templates once** and let many teams instantiate them, without copying YAML between namespaces.
- **Parameterize templates** so the same blueprint adapts to each tenant, environment, or use case.
- **Govern who can use a template** by letting the platform team decide which namespaces are allowed to consume it.
- **Bring your own format**: author templates as inline Go templates with Sprig functions, or point at an existing Helm chart from a public or private registry.
- **Trust the lifecycle**: the operator tracks every resource it creates and removes them when the request is deleted. With drift protection on, it also applies changes and cleans up resources that are no longer rendered.
- **Adopt GitOps naturally**, since both the template and the request to use it are plain Kubernetes resources you can keep in Git.

Template Operator v2 simplifies cluster administration, enhances security, and makes consistent multi-tenancy practical for organizations of any size.
