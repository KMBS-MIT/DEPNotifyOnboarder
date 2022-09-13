# DEPNotify Onboarder

Onboarder is designed to start DEPNotify and enrollment policies using a Pre-Stage 
Enrollment package and Configuration Profile. This addresses some tricky scoping 
issues that could result in skipped policies with Enrollment triggers and allows 
policy logs to be updated quickly since there is no "parent" policy that needs to 
complete first. Since it is designed to run from a pre-stage deploment package,
the onboarding workflow will be ready to run immediately after first user account
creation.

Unlike Jamf's DEPNotifyStarter, Onboarder is configured completely using a profile.
This is advantageous because the Pre-Stage Enrollment package does not need re-signing 
after it is first created and may use a JSON Schema manifest for configuration. Additionally,
no other policies can delay the scripts start and presentation of DEPNotify. Onboarder 
uses a superset of DEPNotify configuration profile settings in the "menu.nomad.DEPNotify" 
domain. See the example plist and JSON Schema manifest included with this script.

Although some benefits will be lost, DEPNotifyOnboarder will work in a traditional 
DEPNotifyStarter setup launched from a policy with an enrollment trigger while taking 
advantage of configuration with a profile.

The DEPNotify Onboarder script was inspired by DEPNotifyStarter (Copyright 2018 Jamf Professional Services)
and uses some code from that sample.

Note: Registration is not supported in this release. It will be added in an upcoming version.

## LICENSE

Permission is hereby granted, free of charge, to any person obtaining a copy of this
software and associated documentation files (the "Software"), to deal in the Software
without restriction, including without limitation the rights to use, copy, modify, merge,
publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons
to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or
substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE
FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.

## Notice

- Launching Self Service on deployment completion currently crashes Self Service when initiated through DEP enrollment. Work around this by using a deploymentComplete custom trigger to launch Self Service.

## Alternatives

- [DEPNotify-Starter](https://github.com/jamf/DEPNotify-Starter)
- [DEPNotify-Starter with Custom Launching Scripts](https://hcsonline.com/support/white-papers/how-to-deploy-depnotify-as-a-jamf-pro-prestage-enrollment-package-with-custom-launching-scripts)
- [Zero-Touch deployment with Jamf Pro and Jamf Connect](https://www.jamf.com/blog/zero-touch-deployment-with-jamf-pro-and-jamf-connect/)
