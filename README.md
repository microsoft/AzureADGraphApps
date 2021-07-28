# Azure AD Graph deprecation toolkit

This PowerShell script lists applications in your tenant that use permissions for Azure AD Graph. [Azure AD Graph will be retired](https://techcommunity.microsoft.com/t5/azure-active-directory-identity/update-your-applications-to-use-microsoft-authentication-library/ba-p/1257363) on June 30, 2022.

If you have applications that use Azure AD Graph permissions and that actively call Azure AD Graph, follow the steps in the [App migration planning checklist](https://docs.microsoft.com/graph/migrate-azure-ad-graph-planning-checklist) to migrate your applications using Azure AD Graph to Microsoft Graph.

> :warning: **Azure AD Graph is deprecated**. To avoid loss of functionality, [migrate your applications to Microsoft Graph](https://docs.microsoft.com/graph/migrate-azure-ad-graph-planning-checklist) before June 30, 2022 when Azure AD Graph API endpoints will stop responding to requests.
>
> Microsoft will continue technical support and apply security fixes for Azure AD Graph until June 30, 2022 when all functionality and support will end. If you fail to migrate your applications to Microsoft Graph before June 30, 2022, you put their functionality and stability at risk.

## Prerequisites

- Azure AD account with [Global Reader](https://docs.microsoft.com/azure/active-directory/roles/permissions-reference#global-reader) role or the permissions granted by that role.
- Microsoft Excel

## Usage

```powershell
.\Create-AppConsentGrantReport.ps1 -AdminUPN globalreader@contoso.onmicrosoft.com -Path .\output.xlsx
```

### Parameters

`AdminUPN`: The user principal name of an administrator in your tenant with **at least Global Reader permissions**.

`Path`: The path to output results to (in Excel format).

## FAQs

**Q: How do I find out if I have Global Reader access?**

**A:** Log in to the Azure Portal, and navigate the [Azure AD Users blade](https://portal.azure.com/#blade/Microsoft_AAD_IAM/UsersManagementMenuBlade/MsGraphUsers). Select your user and go to the Assigned Roles blade. In order to have sufficient permissions to run this script, you should have either a Global Reader or a Global Administrator role assigned to you.

**Q: Can I use Azure AD Graph permissions to call Microsoft Graph?**

**A:** No, you should use the corresponding permissions on Microsoft Graph. For more information, please refer to this [article](https://docs.microsoft.com/en-us/graph/migrate-azure-ad-graph-app-registration)

**Q: Does this script automatically remove my Azure AD Graph permissions in favor of MS Graph permissions?**

**A:** No, this script gives you a list of applications that have Azure AD Graph permissions. You should review these applications, grant them the corresponding Microsoft Graph permissions, migrate their Azure AD Graph API calls to Microsoft Graph, and then remove these Azure AD Graph permissions. Our [Migration Guide](https://docs.microsoft.com/en-us/graph/migrate-azure-ad-graph-planning-checklist) will help you with this process.

## Support

Please see [SUPPORT.md](SUPPORT.md) for support options.

## Contributing

This project welcomes contributions and suggestions.  Most contributions require you to agree to a
Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us
the rights to use your contribution. For details, visit https://cla.opensource.microsoft.com.

When you submit a pull request, a CLA bot will automatically determine whether you need to provide
a CLA and decorate the PR appropriately (e.g., status check, comment). Simply follow the instructions
provided by the bot. You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or
contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.

## Trademarks

This project may contain trademarks or logos for projects, products, or services. Authorized use of Microsoft
trademarks or logos is subject to and must follow
[Microsoft's Trademark & Brand Guidelines](https://www.microsoft.com/en-us/legal/intellectualproperty/trademarks/usage/general).
Use of Microsoft trademarks or logos in modified versions of this project must not cause confusion or imply Microsoft sponsorship.
Any use of third-party trademarks or logos are subject to those third-party's policies.
