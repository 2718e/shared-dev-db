# What to build

want to set up a container that runs a single postgres instance that multiple projects can use (each with it's own db)

Idea being that then if a project wants a db we can just create a particular database rather than having to set up a new container and dockerfiles, compose files before needing them.

Note 1: multiple copies of this container will run

- One inside a lima microvm which also acts as an agent sandbox - then the agents can also have their own project databases isolated from the host.

- Another on the host (real db with actual use data)

Note 2: won't do this now but keep in mind possibly extending the database capabilities beyond default e.g. pgsearch, geo data.

Note 3: want to be able to configure where the data is stored (mount point for postgres data dir?) separately for host and vm versions (maybe an environment variable?)

Note 4: At this time haven't set up docker in the vm. apparently nerdctl and containerd are built in to lima. Not sure if it effects how to define the containers (would I even need docker on host?)