# Contributing to PortKiller

Thank you for your interest in contributing to PortKiller! This document provides guidelines and instructions for contributing to the project.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Making Changes](#making-changes)
- [Pull Request Process](#pull-request-process)
- [Issue Reporting](#issue-reporting)
- [Code Style](#code-style)

## Code of Conduct

By participating in this project, you agree to maintain a respectful and collaborative environment. We welcome contributions from everyone, regardless of experience level.

## Getting Started

1. **Fork the repository** on GitHub
2. **Clone your fork** locally:
   ```bash
   git clone https://github.com/YOUR_USERNAME/port-killer.git
   cd port-killer
   ```
3. **Add upstream remote**:
   ```bash
   git remote add upstream https://github.com/productdevbook/port-killer.git
   ```

## Development Setup

### Prerequisites

- macOS 15.0 or later
- Xcode 16.0 or later (with Swift 6.0)
- Command Line Tools for Xcode

### Building the Project

```bash
# Debug build
swift build

# Release build
swift build -c release

# Run the app
swift run PortKiller

# Build app bundle (creates PortKiller.app)
./scripts/build-app.sh

# Open in Xcode
open Package.swift
```

### Running Tests

```bash
# Run all tests
swift test

# Run specific test
swift test --filter ProcessTypeTests

# Run tests with verbose output
swift test --verbose
```

## Making Changes

### Branch Naming

Use descriptive branch names following this pattern:
- `feature/description` - New features
- `fix/description` - Bug fixes
- `docs/description` - Documentation changes
- `refactor/description` - Code refactoring
- `test/description` - Test additions/changes

Examples:
```bash
git checkout -b feature/add-udp-support
git checkout -b fix/port-scan-timeout
git checkout -b docs/update-readme
```

### Commit Messages

Write clear, concise commit messages:

```
feat: add UDP port scanning support

- Implement UDP socket detection in PortScanner
- Add UDP process type category
- Update UI to display protocol type
```

**Format:**
- First line: Short summary (50 chars or less)
- Blank line
- Detailed description (if needed)
- Reference issues: `Fixes #123`, `Closes #456`

**Commit types:**
- `feat:` - New feature
- `fix:` - Bug fix
- `docs:` - Documentation changes
- `refactor:` - Code refactoring
- `test:` - Test changes
- `chore:` - Maintenance tasks
- `perf:` - Performance improvements

### Code Changes

1. **Follow the style guide** - See [STYLE_GUIDE.md](STYLE_GUIDE.md)
2. **Add tests** - New features should include tests
3. **Update documentation** - Keep docs in sync with code changes
4. **Keep changes focused** - One feature/fix per PR

### Testing Your Changes

Before submitting a PR:

```bash
# 1. Build the project
swift build

# 2. Run tests
swift test

# 3. Test the app bundle
./scripts/build-app.sh
open build/PortKiller.app

# 4. Check for Swift warnings
swift build -c release 2>&1 | grep warning
```

## Pull Request Process

### Before Submitting

- [ ] Code builds without errors
- [ ] All tests pass
- [ ] New code has tests (if applicable)
- [ ] Documentation is updated (if applicable)
- [ ] Code follows style guide
- [ ] Commit messages are clear

### Submitting a PR

1. **Push your branch** to your fork:
   ```bash
   git push origin feature/your-feature
   ```

2. **Create a Pull Request** on GitHub:
   - Use a descriptive title
   - Reference any related issues
   - Provide a clear description of changes
   - Add screenshots/videos for UI changes

3. **PR Template**:
   ```markdown
   ## Description
   Brief description of the changes.

   ## Type of Change
   - [ ] Bug fix
   - [ ] New feature
   - [ ] Documentation update
   - [ ] Code refactoring

   ## Testing
   How did you test these changes?

   ## Checklist
   - [ ] Tests pass
   - [ ] Documentation updated
   - [ ] Code follows style guide

   ## Related Issues
   Fixes #123
   ```

### Review Process

- Maintainers will review your PR
- Address any requested changes
- Once approved, your PR will be merged

### Updating Your PR

If changes are requested:

```bash
# Make changes locally
git add .
git commit -m "fix: address review comments"
git push origin feature/your-feature
```

## Issue Reporting

### Bug Reports

When reporting bugs, include:

1. **Description** - Clear description of the bug
2. **Steps to reproduce**:
   ```
   1. Open PortKiller
   2. Click on '...'
   3. See error
   ```
3. **Expected behavior** - What should happen
4. **Actual behavior** - What actually happens
5. **Environment**:
   - macOS version
   - PortKiller version
   - Relevant system info
6. **Screenshots** - If applicable
7. **Logs** - Console output or error messages

**Example:**
```markdown
**Bug:** Port scanner crashes on empty lsof output

**Steps to reproduce:**
1. Disable all network services
2. Open PortKiller
3. Scan for ports

**Expected:** Shows "No ports found"
**Actual:** App crashes

**Environment:**
- macOS 15.1
- PortKiller v2.4.0

**Error log:**
```
Fatal error: Index out of range
...
```
```

### Feature Requests

When requesting features:

1. **Use case** - Describe the problem you're trying to solve
2. **Proposed solution** - How you envision it working
3. **Alternatives** - Other solutions you've considered
4. **Additional context** - Screenshots, mockups, examples

**Example:**
```markdown
**Feature:** Export port list to CSV

**Use case:** I need to document which ports are in use for compliance reporting.

**Proposed solution:** Add "Export to CSV" button in the main window that saves current port list.

**Alternatives:** Could also support JSON export.
```

### Questions

For questions:
- Check existing [Issues](https://github.com/productdevbook/port-killer/issues)
- Review [README.md](README.md) and documentation
- Open a new issue with the `question` label

## Code Style

See [STYLE_GUIDE.md](STYLE_GUIDE.md) for detailed style guidelines.

**Quick reference:**
- Use Swift 6.0 features and strict concurrency
- Follow Apple's Swift API Design Guidelines
- Use `@Observable` for state management
- Document public APIs with JSDoc-style comments
- Keep files focused and under 300 lines
- Use meaningful variable names

## Development Tips

### Debugging

```bash
# Run with debug output
swift run PortKiller

# Use Xcode for debugging
open Package.swift
# Then use Xcode's debugger
```

### Common Issues

**Issue:** Build fails with "Cannot find module"
**Solution:** Clean build folder and rebuild:
```bash
swift package clean
swift build
```

**Issue:** App doesn't have permissions to scan ports
**Solution:** App must be run from .app bundle, not `swift run`
```bash
./scripts/build-app.sh
open build/PortKiller.app
```

### Useful Commands

```bash
# Format code (if using swift-format)
swift-format -i -r Sources/

# Check for TODO/FIXME comments
grep -r "TODO\|FIXME" Sources/

# View package dependencies
swift package show-dependencies

# Update dependencies
swift package update
```

## Getting Help

- **Issues:** [GitHub Issues](https://github.com/productdevbook/port-killer/issues)
- **Discussions:** GitHub Discussions (if enabled)
- **Twitter:** [@productdevbook](https://x.com/productdevbook)

## License

By contributing, you agree that your contributions will be licensed under the same license as the project.

## Recognition

Contributors will be recognized in:
- Release notes
- GitHub contributors page
- README (for significant contributions)

Thank you for contributing to PortKiller!
