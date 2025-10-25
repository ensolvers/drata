# This project intents to help companies and their personalle to provide evidence of documents for SOC2 using the Drata platform

The project contains:
- Shell scripts for MacOS that automatically take screenshots of the applications that SOC2 requires.
- A Spring Boot application to upload such documents to Drata.

Instead of using the Drata agent that may work in ways we don't now, we provide open source scripts for MacOS and Linux (soon) that take the screenshots and pushes them to the Drata platform. The spring boot application works as an example of how to implement such upload process by following this process:
1. Remove any existing previous evidence documents
2. Upload each provided file according to the type of evidence.

The example uses Esteban's email to map the shell invocation to the user, however, you will have to do the mapping according to the backend you have and security policies. For instance if you have an internal app for time tracking, you can use the code we provided and added to such application to map the shell request to the logged user.
