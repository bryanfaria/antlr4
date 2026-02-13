/*
 * Copyright (c) 2012-2017 The ANTLR Project. All rights reserved.
 * Use of this file is governed by the BSD 3-clause license that
 * can be found in the LICENSE.txt file in the project root.
 */
package org.antlr.v4.test.runtime.erlang;

import org.antlr.v4.test.runtime.*;
import org.antlr.v4.test.runtime.states.CompiledState;
import org.antlr.v4.test.runtime.states.GeneratedState;

import java.io.*;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.*;

import static org.antlr.v4.test.runtime.FileUtils.*;
import static org.antlr.v4.test.runtime.RuntimeTestUtils.FileSeparator;

public class ErlangRunner extends RuntimeRunner {
	@Override
	public String getLanguage() {
		return "Erlang";
	}

	@Override
	protected String getExtension() {
		return "erl";
	}

	@Override
	protected String getLexerSuffix() {
		return "_lexer";
	}

	@Override
	protected String getParserSuffix() {
		return "_parser";
	}

	@Override
	protected String getBaseListenerSuffix() {
		return "_base_listener";
	}

	@Override
	protected String getListenerSuffix() {
		return "_listener";
	}

	@Override
	protected String getBaseVisitorSuffix() {
		return "_base_visitor";
	}

	@Override
	protected String getVisitorSuffix() {
		return "_visitor";
	}

	@Override
	protected String grammarNameToFileName(String grammarName) {
		return toSnakeCase(grammarName);
	}

	@Override
	protected String getTestFileName() {
		return "test_runner";
	}

	@Override
	protected String getRuntimeToolName() {
		return "escript";
	}

	@Override
	protected String getCompilerName() {
		return "erlc";
	}

	@Override
	protected void initRuntime(RunOptions runOptions) throws Exception {
		String cachePath = getCachePath();
		mkdir(cachePath);

		// Copy runtime files to cache
		Path runtimePath = Paths.get(getRuntimePath("Erlang"));
		Path srcPath = runtimePath.resolve("src");
		Path includePath = runtimePath.resolve("include");

		// Create directories
		mkdir(cachePath + FileSeparator + "ebin");
		mkdir(cachePath + FileSeparator + "include");

		// Copy include files
		if (includePath.toFile().exists()) {
			for (File file : includePath.toFile().listFiles()) {
				if (file.getName().endsWith(".hrl")) {
					copyFile(file, new File(cachePath + FileSeparator + "include", file.getName()));
				}
			}
		}

		// Compile runtime source files
		if (srcPath.toFile().exists()) {
			File[] sourceFiles = srcPath.toFile().listFiles((dir, name) -> name.endsWith(".erl"));
			if (sourceFiles != null && sourceFiles.length > 0) {
				List<String> compileArgs = new ArrayList<>();
				compileArgs.add(getCompilerPath());
				compileArgs.add("-o");
				compileArgs.add(cachePath + FileSeparator + "ebin");
				compileArgs.add("-I");
				compileArgs.add(cachePath + FileSeparator + "include");
				compileArgs.add("+debug_info");
				for (File sourceFile : sourceFiles) {
					compileArgs.add(sourceFile.getAbsolutePath());
				}
				Processor.run(compileArgs.toArray(new String[0]), cachePath, null);
			}
		}
	}

	@Override
	protected String grammarParseRuleToRecognizerName(String startRuleName) {
		if (startRuleName == null || startRuleName.length() == 0) {
			return null;
		}
		// Erlang uses lowercase function names
		return startRuleName.toLowerCase();
	}

	@Override
	protected CompiledState compile(RunOptions runOptions, GeneratedState generatedState) {
		Exception ex = null;
		try {
			String cachePath = getCachePath();

			// Copy include files to test directory
			mkdir(getTempDirPath() + FileSeparator + "include");
			File cacheIncludeDir = new File(cachePath + FileSeparator + "include");
			if (cacheIncludeDir.exists()) {
				for (File file : cacheIncludeDir.listFiles()) {
					copyFile(file, new File(getTempDirPath() + FileSeparator + "include", file.getName()));
				}
			}

			// Compile generated Erlang files
			File tempDir = new File(getTempDirPath());
			File[] erlFiles = tempDir.listFiles((dir, name) -> name.endsWith(".erl"));
			if (erlFiles != null && erlFiles.length > 0) {
				mkdir(getTempDirPath() + FileSeparator + "ebin");

				List<String> compileArgs = new ArrayList<>();
				compileArgs.add(getCompilerPath());
				compileArgs.add("-o");
				compileArgs.add(getTempDirPath() + FileSeparator + "ebin");
				compileArgs.add("-I");
				compileArgs.add(getTempDirPath() + FileSeparator + "include");
				compileArgs.add("-pa");
				compileArgs.add(cachePath + FileSeparator + "ebin");
				compileArgs.add("+debug_info");
				for (File erlFile : erlFiles) {
					compileArgs.add(erlFile.getAbsolutePath());
				}
				Processor.run(compileArgs.toArray(new String[0]), getTempDirPath(), null);
			}
		} catch (Exception e) {
			ex = e;
		}
		return new CompiledState(generatedState, ex);
	}

	@Override
	public String[] getExtraRunArgs() {
		return new String[]{};
	}

	@Override
	public Map<String, String> getExecEnvironment() {
		Map<String, String> env = new HashMap<>();
		String cachePath = getCachePath();
		// Add paths to runtime and compiled code
		env.put("ERL_LIBS", cachePath + FileSeparator + "ebin" + File.pathSeparator +
				getTempDirPath() + FileSeparator + "ebin");
		return env;
	}

	/**
	 * Convert CamelCase to snake_case
	 */
	private static String toSnakeCase(String name) {
		StringBuilder result = new StringBuilder();
		for (int i = 0; i < name.length(); i++) {
			char c = name.charAt(i);
			if (Character.isUpperCase(c)) {
				if (i > 0) {
					result.append('_');
				}
				result.append(Character.toLowerCase(c));
			} else {
				result.append(c);
			}
		}
		return result.toString();
	}

	private static void copyFile(File source, File dest) throws IOException {
		try (InputStream is = new FileInputStream(source);
			 OutputStream os = new FileOutputStream(dest)) {
			byte[] buffer = new byte[1024];
			int length;
			while ((length = is.read(buffer)) > 0) {
				os.write(buffer, 0, length);
			}
		}
	}
}
