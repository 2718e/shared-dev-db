# Shared dev db

Database container that can be used for multiple projects.

Intended as a mixture of:

a convenient way to avoid having to define a database separately each time a side project needs one (I'm not sure this goal was actually achieved)

A means of abstracting the database from the application by not including the database in the application projects at all

I primarily use this alongside https://github.com/2718e/harnesses