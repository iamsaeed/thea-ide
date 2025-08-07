# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Theia IDE application - a browser-based IDE framework built on Eclipse Theia v1.63.3. The application provides a web-based development environment with features like file management, integrated terminal, Monaco editor (VS Code engine), and workspace management.

## Key Commands

### Development Commands
- `npm run bundle` - Build the application in development mode
- `npm run watch` - Build with file watching for development
- `npm start` - Start the Theia application (runs on port 3000)
- `npm run rebuild` - Rebuild browser dependencies (run before building)

### Deployment Commands
- `docker-compose up -d --build` - Build and run with Docker
- `docker-compose logs -f` - View application logs
- `docker-compose restart` - Restart the application

## Architecture Overview

### Build System
- Uses Webpack 5 with auto-generated configurations
- **IMPORTANT**: Do NOT modify `gen-webpack.config.js` or `gen-webpack.node.config.js` - these are auto-generated
- Main webpack entry point: `webpack.config.js`

### Project Structure
- `/src-gen/` - Auto-generated source code (frontend and backend)
- `/lib/` - Compiled artifacts separated into frontend/backend
- Frontend entry: `/src-gen/frontend/index.js`
- Backend entry: `/src-gen/backend/main.js` and `/src-gen/backend/server.js`

### Key Technologies
- **Framework**: Eclipse Theia with TypeScript
- **Editor**: Monaco Editor (VS Code engine)
- **Build**: Webpack 5 with code splitting
- **Package Manager**: Yarn v1.x (required, do not use Yarn 2+)
- **Runtime**: Node.js 18+
- **Native Addons**: node-pty, ripgrep, drivelist, parcel-watcher

### Theia Extensions Used
Core extensions that provide IDE functionality:
- `@theia/core` - Core framework
- `@theia/monaco` - Editor integration
- `@theia/filesystem` - File operations
- `@theia/terminal` - Integrated terminal
- `@theia/navigator` - File explorer
- `@theia/workspace` - Workspace management

## Important Notes

1. **Auto-generated Files**: The `/src-gen/` directory contains auto-generated code from Theia CLI. Do not manually edit these files.

2. **Native Dependencies**: The project uses native Node.js addons. When adding new native dependencies, ensure they're compatible with the Node.js version and rebuild using `npm run rebuild`.

3. **Docker Deployment**: The project includes Docker configuration for production deployment. See DEPLOYMENT.md for detailed instructions.

4. **No Test Infrastructure**: Currently, there's no project-level test setup. Individual Theia modules contain their own tests.

5. **Frontend/Backend Communication**: Uses WebSocket-based messaging between frontend and backend through Theia's messaging protocol.